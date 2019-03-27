#!/bin/bash

ARCHS=(			amd64	arm32v6	arm32v7	i386	ppc64le)
DOCKER_ARCHS=(	amd64	arm		arm		386		ppc64le)
ARCH_VARIANTS=(	NONE	v6		v7		NONE	NONE)
QEMU_ARCHS=(	NONE	arm		arm		i386	ppc64le)
TEST_ENABLED=(	1		0		0		1		0)
