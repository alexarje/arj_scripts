import musicalgestures as mg
import os
import glob

# Define the folder containing the MP4 files
folder_path = '.'

# Get a list of all MP4 files in the folder
video_files = glob.glob(os.path.join(folder_path, '*.mp4')) + glob.glob(os.path.join(folder_path, '*.avi'))

# Iterate through each MP4 file and process it
for file_path in video_files:
    print(f'Processing {file_path}')
    
    # Load and resample video file
    v = mg.MgVideo(file_path)
    
    #v.grid(height=500, rows=3, cols=3)
    v.average()
    #v.videograms()
    v.directograms()
    v.motion()
    
    v.audio.waveform()
    v.audio.spectrogram()
    v.audio.tempogram()
    #v.audio.descriptors()
    
    #impact_envelopes = v.impacts(detection=False) # returns an MgFigure with the impact envelopes
    #impact_detection = v.impacts(detection=True, local_mean=0.1, local_maxima=0.15) # returns an MgFigure with the impact detection based on local mean and maxima
    # access impacts envelope data
    #impact_envelopes.data['impact envelopes']
    
    # possible to save the scaled coordinates of the face mask (x1, y1, x2, y2) for each frame in different file formats
    #blur, data = v.blur_faces(save_data=True, data_format='csv')