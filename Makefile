.PHONY: \
	setup \
	ros-setup \
	ros-build \
	ros-doctor \
	ros-smoke \
	validate

setup:
	./scripts/bootstrap.sh

ros-setup:
	./scripts/ros.sh setup

ros-build:
	./scripts/ros.sh build

ros-doctor:
	./scripts/ros.sh doctor

ros-smoke:
	./scripts/ros.sh smoke

validate:
	. .venv/bin/activate && \
	vla-bench validate configs/examples/dummy.yaml
