import os
import librosa
import librosa.display
import numpy as np
import matplotlib.pyplot as plt
from pydub import AudioSegment

# Function to convert m4a to wav
def convert_m4a_to_wav(src_file):
    dst_file = src_file.replace('.m4a', '.wav')
    audio = AudioSegment.from_file(src_file, format='m4a')
    audio.export(dst_file, format='wav')
    return dst_file

# Function to create and save a spectrogram
def create_spectrogram(filepath, output_dir):
    print(f"Processing {filepath}")
    
    # Convert m4a to wav if necessary
    if filepath.lower().endswith('.m4a'):
        try:
            wav_filepath = convert_m4a_to_wav(filepath)
        except Exception as e:
            print(f"Error converting {filepath}: {e}")
            return
    else:
        wav_filepath = filepath

    # Load the audio file
    try:
        y, sr = librosa.load(wav_filepath, sr=None)
    except Exception as e:
        print(f"Error loading {wav_filepath}: {e}")
        return

    # Create a mel spectrogram
    try:
        S = librosa.feature.melspectrogram(y=y, sr=sr)
        S_dB = librosa.power_to_db(S, ref=np.max)
    except Exception as e:
        print(f"Error creating spectrogram for {wav_filepath}: {e}")
        return

    plt.figure(figsize=(16, 9))
    
    # Display the spectrogram
    try:
        librosa.display.specshow(S_dB, sr=sr, x_axis='time', y_axis='mel')
        plt.colorbar(format='%+2.0f dB')
        plt.title('Mel-frequency spectrogram')
    
        # Save the spectrogram
        filename = os.path.splitext(os.path.basename(filepath))[0]
        output_filepath = os.path.join(output_dir, f"{filename}_spectrogram.png")
        plt.savefig(output_filepath)
        plt.close()
        print(f"Saved spectrogram to {output_filepath}")
    except Exception as e:
        print(f"Error displaying/saving spectrogram for {filepath}: {e}")

    # Clean up the temporary wav file if converted
    if filepath.lower().endswith('.m4a'):
        os.remove(wav_filepath)

# Directory containing audio files
input_dir = '.'
# Directory to save spectrograms
output_dir = '.'

# Ensure output directory exists
os.makedirs(output_dir, exist_ok=True)

# Process each audio file in the directory
for filename in os.listdir(input_dir):
    if filename.lower().endswith(('.wav', '.mp3', '.flac', '.ogg', '.m4a')):  # Added .m4a to the list
        filepath = os.path.join(input_dir, filename)
        create_spectrogram(filepath, output_dir)

print("Spectrogram creation process completed.")
