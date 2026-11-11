from glob import glob
import os

from setuptools import find_packages, setup


package_name = "vla_bench_vla"


setup(
    name=package_name,
    version="0.1.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
        (os.path.join("share", package_name, "launch"), glob("launch/*.launch.py")),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    description="Model-agnostic ROS 2 observation/action bridge for VLA Bench",
    license="MIT",
    entry_points={
        "console_scripts": [
            "bridge = vla_bench_vla.bridge:main",
        ],
    },
)
