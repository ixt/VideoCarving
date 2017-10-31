#!/bin/python
import speech_recognition as sr
import argparse
import os

def read_video(file_name):
    try:
        r = sr.Recognizer()
        with sr.AudioFile(file_name) as source:
            audio = r.record(source)
        output = r.recognize_sphinx(audio)
    except IOError as exc:
        output = 'Unable to find the audio file.'
    except sr.UnknownValueError:
        output = 'Error reading audio'
    return output

def main(args=None):
    file_name = open(args.file_name)
    transcription = read_video(file_name)
    print transcription
if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--file-name", help="Enter the file name of a wav file to read from.")
    args = parser.parse_args()
    main(args)

