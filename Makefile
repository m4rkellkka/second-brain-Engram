PROJECT := Engram.xcodeproj
SCHEME := Engram
DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Engram.app
SWIFT_SOURCES := App Packages/EngramKit/Sources Packages/EngramKit/Tests Packages/EngramKit/Package.swift

.PHONY: build test lint format run clean eval-connector demo-graph

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=$(shell uname -m)' -quiet build

test:
	cd Packages/EngramKit && swift test

lint:
	swift format lint --strict --recursive $(SWIFT_SOURCES)

format:
	swift format --in-place --recursive $(SWIFT_SOURCES)

run: build
	open $(APP)

clean:
	rm -rf build Packages/EngramKit/.build

eval-connector: build
	evals/connector/run.sh

demo-graph: build
	COUNT=$(or $(COUNT),2000) scripts/demo-graph.sh
