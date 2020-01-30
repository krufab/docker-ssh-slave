ROOT:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
IMAGE_NAME:=jenkins4eval/ssh-slave

build:
	docker build -f 8/alpine3.9/Dockerfile -t ${IMAGE_NAME}:alpine 8/
	docker build -f 8/stretch/Dockerfile   -t ${IMAGE_NAME}:latest 8/
	docker build -f 11/stretch/Dockerfile  -t ${IMAGE_NAME}:jdk11  11/

.PHONY: tests
tests:
	@FOLDER="8/alpine3.6" bats tests/tests.bats
	@FOLDER="8/stretch"   bats tests/tests.bats
	@FOLDER="11/stretch"  bats tests/tests.bats
