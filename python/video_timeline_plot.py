#!/usr/bin/env python3
# Example usage:
#   python3 video_timeline_plot.py ./videos --output ./plots
#   python3 video_timeline_plot.py video.mp4 --output timeline.png --skip 5
#   python3 video_timeline_plot.py ./videos -o ./plots --use-gpu --max-width 2000
#   python3 video_timeline_plot.py ./videos --output ./plots --audio-mode cqt
"""
Create timeline visualization combining horizontal videogram and audio waveform.

This script generates a two-panel plot for video analysis:
    - Top panel: Horizontal videogram (all frames tiled into one row, time-aligned)
    - Bottom panel: Audio waveform normalized to the same timeline

Features:
    - Batch processing of multiple video formats (mp4, mov, avi, mkv, flv, wmv, webm, m4v)
    - Automatic frame skip calculation based on target videogram width
    - GPU acceleration support (CUDA, VAAPI, QSV)
    - Automatic output path conflict resolution
    - HH:MM:SS time formatting on both panels
    - Handles videos with or without audio tracks
    - Customizable waveform sampling and videogram constraints

Both panels share the same x-axis (time in HH:MM:SS format) for easy synchronization analysis.
Supports batch processing of multiple videos and GPU acceleration via FFmpeg.
"""

import argparse
import subprocess
import shlex
import os
import math
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from pathlib import Path
import librosa
import librosa.display

def run(cmd):
    """Run shell command and return combined output."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout + result.stderr, result.returncode

def get_video_info(video_path):
    """Get video duration, width, height, and frame count."""
    # Get duration
    cmd = f'ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 {shlex.quote(video_path)}'
    out, _ = run(cmd)
    duration = float(out.strip())
    
    # Get video properties
    cmd = f'ffprobe -v error -select_streams v:0 -show_entries stream=width,height,nb_frames -of csv=p=0 {shlex.quote(video_path)}'
    out, _ = run(cmd)
    parts = out.strip().split(',')
    width = int(parts[0])
    height = int(parts[1])
    
    # Get frame count (use count_packets if nb_frames unavailable)
    try:
        framecount = int(parts[2]) if len(parts) > 2 and parts[2] else None
    except (ValueError, IndexError):
        framecount = None
    
    if not framecount:
        cmd = f'ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 {shlex.quote(video_path)}'
        out, _ = run(cmd)
        framecount = int(out.strip())
    
    return duration, width, height, framecount

def get_non_conflicting_path(filepath):
    """Return a non-conflicting output path by appending counter if file exists."""
    if not os.path.exists(filepath):
        return filepath
    
    base, ext = os.path.splitext(filepath)
    counter = 1
    while os.path.exists(f"{base}_{counter}{ext}"):
        counter += 1
    return f"{base}_{counter}{ext}"

def extract_videogram(video_path, output_path, skip=None, target_width=1920, max_width=None, hwaccel=None):
    """Extract horizontal videogram (one row of frames)."""
    duration, width, height, framecount = get_video_info(video_path)
    
    # Auto-calculate skip if not specified
    if skip is None:
        skip = max(1, int(math.ceil(framecount / target_width)))
    
    tiles = int(math.ceil(framecount / skip))
    
    print(f"  Extracting videogram: {framecount} frames -> {tiles} tiles (skip={skip})")
    
    vf = f"select='not(mod(n\\,{skip}))',scale=1:{height}:sws_flags=area,normalize,tile={tiles}x1"
    if max_width and max_width > 0:
        vf += f",scale=min(iw\\,{max_width}):-1"
    
    cmd_parts = ['ffmpeg', '-hide_banner', '-loglevel', 'error']
    if hwaccel:
        cmd_parts += ['-hwaccel', hwaccel]
    cmd_parts += ['-y', '-i', video_path, '-frames', '1', '-vf', vf, output_path]
    
    result = subprocess.run(cmd_parts, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"FFmpeg videogram failed: {result.stderr}")
    
    return duration, tiles

def extract_waveform_data(video_path, samples=2000):
    """Extract audio waveform data as numpy array."""
    print(f"  Extracting audio waveform ({samples} samples)...")
    
    # Extract audio to raw PCM
    cmd = (
        f'ffmpeg -hide_banner -loglevel error -i {shlex.quote(video_path)} '
        f'-vn -ac 1 -ar 8000 -f s16le -'
    )
    
    result = subprocess.run(cmd, shell=True, capture_output=True)
    
    if result.returncode != 0:
        print("  Warning: No audio stream found or extraction failed")
        return None
    
    # Convert to numpy array
    audio_data = np.frombuffer(result.stdout, dtype=np.int16)
    
    if len(audio_data) == 0:
        return None
    
    # Downsample to target number of samples
    if len(audio_data) > samples:
        step = len(audio_data) // samples
        audio_data = audio_data[::step][:samples]
    
    # Normalize to [-1, 1]
    audio_data = audio_data.astype(np.float32) / 32768.0
    
    return audio_data

def extract_cqt_spectrogram(video_path, sr=8000, hop_length=512, n_bins=72, bins_per_octave=12):
    """Extract CQT spectrogram from video audio."""
    print(f"  Extracting CQT spectrogram...")
    
    # Extract audio to raw PCM
    cmd = (
        f'ffmpeg -hide_banner -loglevel error -i {shlex.quote(video_path)} '
        f'-vn -ac 1 -ar {sr} -f s16le -'
    )
    
    result = subprocess.run(cmd, shell=True, capture_output=True)
    
    if result.returncode != 0:
        print("  Warning: No audio stream found or extraction failed")
        return None, None
    
    # Convert to numpy array
    audio_data = np.frombuffer(result.stdout, dtype=np.int16)
    
    if len(audio_data) == 0:
        return None, None
    
    # Normalize to [-1, 1]
    audio_data = audio_data.astype(np.float32) / 32768.0
    
    # Compute CQT spectrogram
    cqt = librosa.cqt(audio_data, sr=sr, hop_length=hop_length, n_bins=n_bins, bins_per_octave=bins_per_octave)
    cqt_db = librosa.power_to_db(np.abs(cqt), ref=np.max)
    
    return cqt_db, sr

def create_timeline_plot(video_path, output_path, skip=None, target_width=1920, max_width=None, waveform_samples=None, hwaccel=None, audio_mode='waveform'):
    """Create combined videogram + waveform timeline plot."""
    basename = Path(video_path).stem
    print(f"\nProcessing: {basename}")
    
    # Temporary videogram image
    temp_vg = f"/tmp/vg_{basename}.png"
    
    try:
        # Extract videogram
        duration, tiles = extract_videogram(video_path, temp_vg, skip=skip, target_width=target_width, max_width=max_width, hwaccel=hwaccel)
        
        # Extract audio based on mode
        if audio_mode == 'cqt':
            audio_data, sr = extract_cqt_spectrogram(video_path)
        else:
            # Auto-scale waveform samples to match videogram width if not specified
            if waveform_samples is None:
                waveform_samples = tiles
            
            # Extract waveform
            audio_data = extract_waveform_data(video_path, samples=waveform_samples)
        
        # Load videogram image
        from PIL import Image
        vg_img = Image.open(temp_vg)
        vg_array = np.array(vg_img)
        vg_height = vg_array.shape[0]
        
        # Create figure with two subplots
        fig = plt.figure(figsize=(16, 8))
        # Adjust height ratios based on audio mode
        height_ratios = [1, 1] if audio_mode == 'cqt' else [2, 1]
        gs = GridSpec(2, 1, height_ratios=height_ratios, hspace=0.02)
        
        # Plot videogram
        ax1 = fig.add_subplot(gs[0])
        ax1.imshow(vg_array, aspect='auto', extent=[0, duration, vg_height, 0])
        ax1.set_ylabel('pixels', fontsize=11)
        
        # Format x-axis with time labels (HH:MM:SS)
        from matplotlib.ticker import FuncFormatter
        def format_time(x, pos):
            hours = int(x // 3600)
            mins = int((x % 3600) // 60)
            secs = int(x % 60)
            return f'{hours:02d}:{mins:02d}:{secs:02d}'
        
        ax1.xaxis.set_major_formatter(FuncFormatter(format_time))
        # Hide x-axis labels on the videogram but keep tick marks
        ax1.tick_params(axis='x', labelbottom=False, bottom=True)
        
        # Plot audio (waveform or spectrogram)
        ax2 = fig.add_subplot(gs[1], sharex=ax1)
        
        if audio_data is not None and len(audio_data) > 0:
            if audio_mode == 'cqt':
                # Plot CQT spectrogram
                hop_length = 512
                sr = 8000
                n_bins = 72
                bins_per_octave = 12
                
                # Create time axis for CQT
                frames = audio_data.shape[1]
                time_axis = librosa.frames_to_time(np.arange(frames), sr=sr, hop_length=hop_length)
                
                # Scale time axis to match video duration
                if len(time_axis) > 0 and time_axis[-1] > 0:
                    time_scale = duration / time_axis[-1]
                    time_axis = time_axis * time_scale
                
                # Plot spectrogram
                im = ax2.imshow(audio_data, aspect='auto', origin='lower', cmap='magma',
                              extent=[0, duration, 0, audio_data.shape[0]])
                
                # Add musical note labels on y-axis
                frequencies = librosa.cqt_frequencies(n_bins=n_bins, fmin=32.7, bins_per_octave=bins_per_octave)
                midi_notes = librosa.hz_to_midi(frequencies)
                
                # Set y-axis ticks at every octave (12 bins)
                octave_bins = np.arange(0, n_bins, bins_per_octave)
                note_labels = [librosa.midi_to_note(int(midi_notes[i]), octave=True) for i in octave_bins]
                
                ax2.set_yticks(octave_bins)
                ax2.set_yticklabels(note_labels, fontsize=9)
                ax2.set_ylabel('Musical Notes', fontsize=11)
            else:
                # Plot waveform
                time_axis = np.linspace(0, duration, len(audio_data))
                ax2.fill_between(time_axis, audio_data, alpha=0.6, color='steelblue', label='Waveform')
                ax2.plot(time_axis, audio_data, color='darkblue', linewidth=0.5, alpha=0.8)
                ax2.axhline(y=0, color='gray', linestyle='--', linewidth=0.5, alpha=0.5)
                ax2.set_ylim(-1.1, 1.1)
                ax2.set_ylabel('Amplitude', fontsize=11)
        else:
            ax2.text(duration/2, 0.5, 'No audio track', ha='center', va='center', 
                    fontsize=12, color='gray', style='italic')
            ax2.set_ylabel('Audio (none)', fontsize=11)
        
        
        # Use same HH:MM:SS formatter for waveform x-axis
        def format_time_hms(x, pos):
            hours = int(x // 3600)
            mins = int((x % 3600) // 60)
            secs = int(x % 60)
            return f'{hours:02d}:{mins:02d}:{secs:02d}'
        ax2.xaxis.set_major_formatter(FuncFormatter(format_time_hms))
        
        fig.subplots_adjust(hspace=0.02)
        plt.savefig(output_path, dpi=150, bbox_inches='tight')
        plt.close()
        
        print(f"  ✓ Saved: {output_path}")
        
    finally:
        # Clean up temp file
        if os.path.exists(temp_vg):
            os.remove(temp_vg)

def process_folder(folder_path, output_dir, skip=None, target_width=1920, max_width=None, waveform_samples=None, hwaccel=None, audio_mode='waveform'):
    """Process all videos in a folder."""
    os.makedirs(output_dir, exist_ok=True)
    
    video_extensions = {'.mp4', '.mov', '.avi', '.mkv', '.flv', '.wmv', '.webm', '.m4v'}
    videos = [f for f in os.listdir(folder_path) 
              if os.path.splitext(f)[1].lower() in video_extensions]
    
    if not videos:
        print(f"No video files found in {folder_path}")
        return
    
    print(f"Found {len(videos)} video(s) to process\n")
    
    for idx, video in enumerate(videos, 1):
        video_path = os.path.join(folder_path, video)
        basename = Path(video).stem
        output_path = os.path.join(output_dir, f'{basename}_timeline.png')
        
        # Skip if already exists
        if os.path.exists(output_path):
            print(f"[{idx}/{len(videos)}] {basename} (skipped - already exists)")
            continue
        
        print(f"[{idx}/{len(videos)}]")
        try:
            create_timeline_plot(video_path, output_path, skip=skip, target_width=target_width,
                               max_width=max_width, waveform_samples=waveform_samples, hwaccel=hwaccel, audio_mode=audio_mode)
        except Exception as e:
            print(f"  ✗ Error: {e}")
            continue
    
    print(f"\n✓ Processed {len(videos)} video(s)")

def main():
    parser = argparse.ArgumentParser(
        description='Create timeline plots with videogram and waveform for video files.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process all videos in a folder
  python3 video_timeline_plot.py ./videos --output ./plots
  
  # Skip every 5 frames for speed, limit videogram width
  python3 video_timeline_plot.py ./videos -o ./plots --skip 5 --max-width 2000
  
  # Single video with GPU acceleration
  python3 video_timeline_plot.py video.mp4 -o output.png --use-gpu
        """
    )
    
    parser.add_argument('input', help='Video file or folder containing videos')
    parser.add_argument('--output', '-o', required=True, help='Output file (for single video) or folder (for multiple)')
    parser.add_argument('--target-width', type=int, default=1920, help='Target videogram width in pixels (auto-calculates skip)')
    parser.add_argument('--skip', type=int, default=None, help='Manual frame skip factor (overrides auto-calculation)')
    parser.add_argument('--max-width', type=int, default=None, help='Maximum videogram width after scaling (optional constraint)')
    parser.add_argument('--waveform-samples', type=int, default=None, help='Number of waveform samples (auto-matches videogram if unset)')
    parser.add_argument('--hwaccel', default=None, help='FFmpeg hardware accel (cuda, vaapi, qsv)')
    parser.add_argument('--use-gpu', action='store_true', help='Use GPU acceleration (auto)')
    parser.add_argument('--audio-mode', choices=['waveform', 'cqt'], default='waveform', help='Audio visualization mode: waveform or CQT spectrogram')
    
    args = parser.parse_args()
    
    hwaccel = 'auto' if args.use_gpu else args.hwaccel
    
    if os.path.isfile(args.input):
        # Single video
        create_timeline_plot(args.input, args.output, skip=args.skip, target_width=args.target_width,
                           max_width=args.max_width, waveform_samples=args.waveform_samples,
                           hwaccel=hwaccel, audio_mode=args.audio_mode)
    elif os.path.isdir(args.input):
        # Folder of videos
        process_folder(args.input, args.output, skip=args.skip, target_width=args.target_width,
                      max_width=args.max_width, waveform_samples=args.waveform_samples,
                      hwaccel=hwaccel, audio_mode=args.audio_mode)
    else:
        print(f"Error: {args.input} is not a valid file or directory")
        return 1

if __name__ == '__main__':
    main()
