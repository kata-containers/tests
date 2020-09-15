# Copyright (c) 2020 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0

# Set up an image with 'tensorflow' installed
# for inference fp32 model

# Usage: FROM [image name]
FROM intelaipg/intel-optimized-tensorflow:1.15.0-mkl-py3

# Version of the Dockerfile
LABEL DOCKERFILE_VERSION="1.0"

ENV TEST_DIRECTORY "tensorflow"
ENV MODELS_URL "https://github.com/tensorflow/models.git"
ENV INTELAI_URL "https://github.com/IntelAI/models.git"
ENV PRETRAINED_MODEL_URL "https://storage.googleapis.com/intel-optimized-tensorflow/models/v1_5/inceptionv3_fp32_pretrained_model.pb"
ENV GRAPH_MODEL_URL "https://zenodo.org/record/2535873/files/resnet50_v1.pb"
ENV INTELAI_VERSION "v1.5.0"

RUN apt-get update && \
	apt-get install -y git numactl google-perftools wget && \
	apt-get remove -y unattended-upgrades && \
	mkdir ${TEST_DIRECTORY} && cd ${TEST_DIRECTORY} && \
	git clone --depth 1 ${MODELS_URL} /${TEST_DIRECTORY}/models && \
	git clone -b ${INTELAI_VERSION} --depth 1 ${INTELAI_URL} /${TEST_DIRECTORY}/intel_models && \
	wget -q -P /${TEST_DIRECTORY} ${PRETRAINED_MODEL_URL} && \
	wget -q -P /${TEST_DIRECTORY} ${GRAPH_MODEL_URL}

WORKDIR ${TEST_DIRECTORY}
CMD ["/bin/bash"]
