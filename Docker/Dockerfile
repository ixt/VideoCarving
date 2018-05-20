FROM debian:stretch-slim
RUN set -ex; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		git \
        	build-essential \
		python \
		python-dev \
		python-pip \
		python-wheel \
        	python-setuptools \
		libxml2-dev \
		libxslt1-dev \
        	libespeak-dev \
        	libpulse-dev \
        	mediainfo \
        	espeak \
		ffmpeg \
        	sshfs \
        	swig \
        	wget \
        	bc \
	; \
    pip install \
        numpy \
        wheel \
    ; \
    pip install \
        aeneas \
        youtube-dl \
        SpeechRecognition \
        pocketsphinx \
        fuzzy \
    ; \
    git clone https://github.com/ixt/VideoCarving ; \
    cd VideoCarving; \
    bash WordEstimates.sh; \
	rm -rf /var/lib/apt/lists/*
