from flask import Flask, request, jsonify, Response
import yt_dlp
import subprocess
import tempfile
import os
import threading
import time
import uuid
import queue
import logging
from urllib.parse import unquote
from functools import lru_cache
import json
import numpy as np

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class OptimizedChunkedMusicServer:
    def __init__(self):
        self.temp_dir = tempfile.mkdtemp()
        self.active_streams = {}
        self.default_chunk_size = 8192
        self.buffer_target = 10
        self.cache_dir = os.path.join(self.temp_dir, "cache")
        os.makedirs(self.cache_dir, exist_ok=True)

        # Audio quality monitoring
        self.quality_metrics = {}

        # Cleanup old sessions periodically
        self.cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
        self.cleanup_thread.start()

    def _cleanup_loop(self):
        """Periodically clean up inactive sessions"""
        while True:
            time.sleep(60)  # Check every minute
            current_time = time.time()
            to_remove = []

            for session_id, session in self.active_streams.items():
                if not session['is_active'] and current_time - session['last_activity'] > 300:
                    to_remove.append(session_id)

            for session_id in to_remove:
                self.cleanup_session(session_id)
                logger.info(f"Cleaned up inactive session: {session_id}")

    def validate_audio_config(self, config):
        # Accept any sample rate >= 8000
        requested_rate = int(config.get('sample_rate', 22050))
        # Optionally, check if it's in a supported list
        supported_rates = [48000, 32000, 22050, 16000, 11025, 8000]
        if requested_rate not in supported_rates:
            requested_rate = 22050  # fallback

        return {
            'sample_rate': requested_rate,
            'channels': 1,
            'bit_depth': 8,
            'chunk_size': min(32768, max(1024, int(config.get('chunk_size', self.default_chunk_size)))),
            'format': 'pcm',
            'normalize': config.get('normalize', True),
            'volume': min(0.9, max(0.1, float(config.get('volume', 0.7)))),  # Lower default for 8-bit
            'enhance_8bit': config.get('enhance_8bit', True),
            'dither_method': config.get('dither_method', 'triangular_hp'),
            'eq_preset': config.get('eq_preset', 'psychoacoustic')
        }

    @lru_cache(maxsize=100)
    def search_youtube(self, query):
        """Search YouTube with caching"""
        ydl_opts = {
            'quiet': True,
            'no_warnings': True,
            'extract_flat': True,
            'playlist_items': '1:20',
            'ignoreerrors': True
        }

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(f"ytsearch20:{query}", download=False)

            results = []
            for entry in info.get('entries', []):
                if entry:
                    results.append({
                        'id': entry.get('id'),
                        'title': entry.get('title', 'Unknown'),
                        'artist': entry.get('uploader', 'Unknown'),
                        'duration': entry.get('duration', 0),
                        'thumbnail': entry.get('thumbnail'),
                        'view_count': entry.get('view_count', 0)
                    })

            return results
        except Exception as e:
            logger.error(f"Search error: {e}")
            return []

    def get_stream_info(self, video_id):
        """Get stream URL and metadata"""
        cache_file = os.path.join(self.cache_dir, f"{video_id}.json")

        # Check cache
        if os.path.exists(cache_file):
            try:
                with open(cache_file, 'r') as f:
                    cached = json.load(f)
                if time.time() - cached['timestamp'] < 3600:  # 1 hour cache
                    return cached['data']
            except:
                pass

        ydl_opts = {
            'format': 'bestaudio[ext=m4a]/bestaudio/best',
            'quiet': True,
            'no_warnings': True,
            'extract_flat': False,
            'skip_download': True
        }

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(f"https://youtube.com/watch?v={video_id}", download=False)

            data = {
                'url': info['url'],
                'title': info.get('title', 'Unknown'),
                'artist': info.get('uploader', 'Unknown'),
                'duration': info.get('duration', 0)
            }

            # Cache the result
            with open(cache_file, 'w') as f:
                json.dump({'timestamp': time.time(), 'data': data}, f)

            return data
        except Exception as e:
            logger.error(f"Failed to get stream info: {e}")
            return None

    def get_8bit_optimized_filters(self, config):
        """Generate filters optimized for 8-bit playback - using only common filters"""
        filters = []

        # Convert to mono if not already
        filters.append('aformat=channel_layouts=mono')

        # High-pass filter to remove DC and subsonic content
        filters.append('highpass=f=20')

        # Psychoacoustic EQ curve for 8-bit - using individual equalizer filters
        if config.get('eq_preset') == 'psychoacoustic':
            # Reduce sub-bass
            filters.append('equalizer=f=80:t=h:g=-3:w=100')
            # Slight reduction in low-mids
            filters.append('equalizer=f=250:t=h:g=-1:w=200')
            # Boost presence for clarity
            filters.append('equalizer=f=3000:t=h:g=3:w=1000')
            # Boost high frequencies
            filters.append('equalizer=f=8000:t=h:g=2:w=2000')

        # Simple compression using compand
        filters.append('compand=attacks=0.003:decays=0.05:points=-80/-80|-60/-60|-40/-30|-20/-15|-10/-10|-5/-8|0/-5:soft-knee=6:gain=5')

        # Loudness normalization
        if config['normalize']:
            filters.append('loudnorm=I=-14:TP=-1:LRA=7')

        # Volume adjustment
        filters.append(f'volume={config["volume"]}')

        # Limiter to prevent clipping
        filters.append('alimiter=limit=0.95:attack=1:release=10')

        # Resample to target rate
        filters.append(f'aresample={config["sample_rate"]}')

        # Final format conversion with dithering
        # filters.append('aformat=sample_fmts=s8')

        return ','.join(filters)

    def calculate_audio_metrics(self, chunk_data, session_id):
        """Calculate metrics for audio quality monitoring"""
        try:
            # Convert to numpy array
            audio = np.frombuffer(chunk_data, dtype=np.int8)

            # Calculate RMS level
            rms = np.sqrt(np.mean(audio.astype(np.float32)**2))

            # Calculate dynamic range usage
            min_val = np.min(audio)
            max_val = np.max(audio)
            dynamic_range = max_val - min_val

            # Detect clipping
            clipping = np.sum(np.abs(audio) >= 127) / len(audio)

            # Calculate frequency content (simple zero-crossing rate)
            zero_crossings = np.sum(np.diff(np.sign(audio)) != 0)
            zcr = zero_crossings / len(audio)

            metrics = {
                'rms_level': float(rms),
                'dynamic_range': int(dynamic_range),
                'clipping_ratio': float(clipping),
                'peak_level': int(max(abs(min_val), abs(max_val))),
                'zero_crossing_rate': float(zcr),
                'timestamp': time.time()
            }

            # Store metrics for monitoring
            if session_id not in self.quality_metrics:
                self.quality_metrics[session_id] = []

            self.quality_metrics[session_id].append(metrics)

            # Keep only recent metrics (last 100)
            if len(self.quality_metrics[session_id]) > 100:
                self.quality_metrics[session_id] = self.quality_metrics[session_id][-100:]

            return metrics
        except Exception as e:
            logger.error(f"Error calculating audio metrics: {e}")
            return None

    def create_stream_session(self, video_id, audio_config):
        """Create a new streaming session"""
        session_id = str(uuid.uuid4())
        config = self.validate_audio_config(audio_config)

        session = {
            'session_id': session_id,
            'video_id': video_id,
            'audio_config': config,
            'chunk_queue': queue.Queue(maxsize=30),
            'is_active': True,
            'error': None,
            'ready': threading.Event(),
            'total_chunks_sent': 0,
            'start_time': time.time(),
            'last_activity': time.time(),
            'metadata': None,
            'process': None
        }

        self.active_streams[session_id] = session

        thread = threading.Thread(
            target=self.stream_worker,
            args=(session,),
            daemon=True
        )
        thread.start()

        return session_id, config

    def stream_worker(self, session):
        """Worker thread for streaming audio with 8-bit optimizations"""
        session_id = session['session_id']
        video_id = session['video_id']
        config = session['audio_config']

        try:
            # Get stream info
            stream_info = self.get_stream_info(video_id)
            if not stream_info:
                raise Exception("Failed to get stream URL")

            session['metadata'] = stream_info
            stream_url = stream_info['url']

            # Use optimized 8-bit filter chain
            filter_str = self.get_8bit_optimized_filters(config)

            cmd = [
                'ffmpeg',
                '-reconnect', '1',
                '-reconnect_streamed', '1',
                '-reconnect_delay_max', '5',
                '-i', stream_url,
                '-af', filter_str,
                '-f', 's8',
                '-acodec', 'pcm_s8',
                '-ac', '1',
                '-'
            ]

            logger.info(f"Starting FFmpeg with command: {' '.join(cmd[:10])}...")  # Log first part of command

            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                bufsize=0
            )

            session['process'] = process

            # Monitor stderr in separate thread for errors
            def stderr_reader():
                for line in process.stderr:
                    decoded_line = line.decode('utf-8', errors='ignore').strip()
                    if decoded_line:
                        if 'error' in decoded_line.lower():
                            logger.warning(f"FFmpeg error in session {session_id}: {decoded_line}")
                        else:
                            logger.debug(f"FFmpeg output: {decoded_line}")

            stderr_thread = threading.Thread(target=stderr_reader, daemon=True)
            stderr_thread.start()

            chunk_size = config['chunk_size']
            buffer = b''
            first_chunk_sent = False
            consecutive_errors = 0
            chunks_processed = 0

            while session['is_active'] and process.poll() is None:
                try:
                    raw_data = process.stdout.read(4096)
                    if not raw_data:
                        consecutive_errors += 1
                        if consecutive_errors > 5:
                            break
                        time.sleep(0.1)
                        continue

                    consecutive_errors = 0
                    buffer += raw_data

                    while len(buffer) >= chunk_size:
                        chunk_data = buffer[:chunk_size]
                        buffer = buffer[chunk_size:]

                        # Calculate audio metrics periodically
                        if chunks_processed % 10 == 0:  # Every 10th chunk
                            metrics = self.calculate_audio_metrics(chunk_data, session_id)
                            if metrics and metrics['clipping_ratio'] > 0.01:
                                logger.warning(f"High clipping detected in session {session_id}: {metrics['clipping_ratio']:.2%}")

                        try:
                            session['chunk_queue'].put(chunk_data, timeout=0.5)
                            session['total_chunks_sent'] += 1
                            session['last_activity'] = time.time()
                            chunks_processed += 1

                            if not first_chunk_sent:
                                session['ready'].set()
                                first_chunk_sent = True
                                logger.info(f"First chunk ready for session {session_id}")

                        except queue.Full:
                            # Client is slow, skip some chunks to catch up
                            logger.debug(f"Buffer full for session {session_id}, dropping chunk")
                            try:
                                session['chunk_queue'].get_nowait()
                            except:
                                pass

                except Exception as e:
                    logger.error(f"Error reading stream data: {e}")
                    consecutive_errors += 1
                    if consecutive_errors > 10:
                        break
                    time.sleep(0.1)

            # Send remaining buffer
            if buffer and session['is_active']:
                try:
                    session['chunk_queue'].put(buffer, timeout=0.5)
                except:
                    pass

            # Clean up process
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except:
                    process.kill()

        except Exception as e:
            logger.error(f"Stream worker error for session {session_id}: {e}")
            session['error'] = str(e)
        finally:
            session['is_active'] = False
            # Signal end of stream
            try:
                session['chunk_queue'].put(None, timeout=0.1)
            except:
                pass
            session['ready'].set()
            logger.info(f"Stream worker ended for session {session_id}")

    def get_next_chunk(self, session_id):
        """Get next audio chunk for session"""
        session = self.active_streams.get(session_id)
        if not session:
            return None

        session['last_activity'] = time.time()

        # Wait for stream to be ready
        if not session['ready'].wait(timeout=15):
            logger.warning(f"Stream timeout for session {session_id}")
            return None

        try:
            chunk = session['chunk_queue'].get(timeout=2.0)
            return chunk
        except queue.Empty:
            # Check if stream is still active
            if session['is_active']:
                return b''  # Return empty chunk to keep connection alive
            return None

    def cleanup_session(self, session_id):
        """Clean up streaming session"""
        session = self.active_streams.pop(session_id, None)
        if session:
            session['is_active'] = False
            if session.get('process'):
                try:
                    session['process'].terminate()
                    session['process'].wait(timeout=2)
                except:
                    try:
                        session['process'].kill()
                    except:
                        pass

            # Clean up quality metrics
            self.quality_metrics.pop(session_id, None)

            logger.info(f"Cleaned up session {session_id}")

# Initialize server
music_server = OptimizedChunkedMusicServer()

# API Routes
@app.route('/')
def search_endpoint():
    """Search for music"""
    search_query = request.args.get('search')
    if not search_query:
        return jsonify({'error': 'No search query provided'}), 400

    search_query = unquote(search_query)
    results = music_server.search_youtube(search_query)
    return jsonify(results)

@app.route('/audio_capabilities')
def audio_capabilities():
    """Get server audio capabilities with 8-bit optimizations"""
    return jsonify({
        'supported_sample_rates': [32000, 22050, 16000, 11025, 8000],  # Lower rates for 8-bit
        'supported_bit_depths': [8],
        'supported_channels': [1],
        'supported_formats': ['pcm'],
        'features': [
            'normalize',
            'volume_control',
            'compression',
            'psychoacoustic_eq',
            'quality_monitoring',
            'dynamic_range_optimization'
        ],
        'eq_presets': [
            'psychoacoustic',
            'flat',
            'voice',
            'music'
        ],
        'default_config': {
            'sample_rate': 22050,  # Optimal for 8-bit
            'channels': 1,
            'bit_depth': 8,
            'chunk_size': 8192,
            'format': 'pcm',
            'normalize': True,
            'volume': 0.7,
            'enhance_8bit': True,
            'eq_preset': 'psychoacoustic'
        },
        'max_buffer_size': 30,
        'target_latency_ms': 200,
        'version': '3.0'
    })

@app.route('/start_stream', methods=['POST'])
def start_stream():
    """Start a new streaming session"""
    data = request.get_json() or {}
    video_id = data.get('id') or request.args.get('id')

    if not video_id:
        return jsonify({'error': 'No video ID provided'}), 400

    audio_config = data.get('audio_config', {})

    try:
        session_id, validated_config = music_server.create_stream_session(video_id, audio_config)

        return jsonify({
            'session_id': session_id,
            'chunk_endpoint': f'/chunk/{session_id}',
            'audio_config': validated_config,
            'status': 'started',
            'estimated_first_chunk_ms': 1000
        })
    except Exception as e:
        logger.error(f"Failed to start stream: {e}")
        return jsonify({'error': 'Failed to create stream session'}), 500

@app.route('/chunk/<session_id>')
def get_chunk(session_id):
    """Get next audio chunk"""
    chunk = music_server.get_next_chunk(session_id)

    if chunk is None:
        music_server.cleanup_session(session_id)
        return Response('', status=204)

    return Response(
        chunk,
        content_type='application/octet-stream',
        headers={
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'X-Chunk-Size': str(len(chunk)),
            'X-Session-Active': 'true' if chunk else 'false'
        }
    )

@app.route('/stop_stream/<session_id>', methods=['POST'])
def stop_stream(session_id):
    """Stop streaming session"""
    music_server.cleanup_session(session_id)
    return jsonify({'status': 'stopped'})

@app.route('/stream_info/<session_id>')
def stream_info(session_id):
    """Get streaming session info"""
    session = music_server.active_streams.get(session_id)
    if not session:
        return jsonify({'error': 'Session not found'}), 404

    return jsonify({
        'session_id': session_id,
        'is_active': session['is_active'],
        'is_ready': session['ready'].is_set(),
        'chunks_buffered': session['chunk_queue'].qsize(),
        'total_chunks_sent': session['total_chunks_sent'],
        'elapsed_seconds': round(time.time() - session['start_time'], 2),
        'audio_config': session['audio_config'],
        'metadata': session.get('metadata'),
        'error': session.get('error')
    })

@app.route('/stream_quality/<session_id>')
def stream_quality(session_id):
    """Get audio quality metrics for a session"""
    metrics = music_server.quality_metrics.get(session_id, [])

    if not metrics:
        return jsonify({'error': 'No metrics available'}), 404

    # Calculate averages
    recent_metrics = metrics[-10:] if len(metrics) > 10 else metrics

    avg_metrics = {
        'avg_rms_level': np.mean([m['rms_level'] for m in recent_metrics]),
        'avg_dynamic_range': np.mean([m['dynamic_range'] for m in recent_metrics]),
        'avg_clipping_ratio': np.mean([m['clipping_ratio'] for m in recent_metrics]),
        'max_peak_level': max([m['peak_level'] for m in recent_metrics]),
        'recent_samples': len(recent_metrics),
        'total_samples': len(metrics)
    }

    return jsonify({
        'session_id': session_id,
        'current_metrics': metrics[-1] if metrics else None,
        'average_metrics': avg_metrics,
        'quality_score': calculate_quality_score(avg_metrics)
    })

def calculate_quality_score(metrics):
    """Calculate an overall quality score from metrics"""
    score = 100.0

    # Penalize clipping
    score -= metrics['avg_clipping_ratio'] * 500

    # Penalize low dynamic range
    if metrics['avg_dynamic_range'] < 100:
        score -= (100 - metrics['avg_dynamic_range']) * 0.2

    # Penalize very low or high RMS
    ideal_rms = 40.0
    rms_deviation = abs(metrics['avg_rms_level'] - ideal_rms)
    score -= rms_deviation * 0.5

    return max(0, min(100, score))

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'active_streams': len(music_server.active_streams),
        'server_time': time.time(),
        'version': '3.0'
    })

@app.errorhandler(Exception)
def handle_error(e):
    logger.error(f"Unhandled error: {e}")
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    print("Starting Optimized Music Streaming Server v3.0...")
    print("8-bit audio optimizations enabled")
    print("Server running on http://0.0.0.0:5000")
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)