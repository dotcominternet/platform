.PHONY: build package run stop run-client run-server stop-client stop-server restart-server restart-client start-docker clean-dist clean nuke check-style check-unit-tests test dist setup-mac prepare-enteprise build-linux build-osx build-windows

# Build Flags
BUILD_NUMBER ?= $(BUILD_NUMBER:)
BUILD_DATE = $(shell date -u)
BUILD_HASH = $(shell git rev-parse HEAD)
# If we don't set the build number it defaults to dev
ifeq ($(BUILD_NUMBER),)
	BUILD_NUMBER := dev
endif
BUILD_ENTERPRISE_DIR ?= ../enterprise
BUILD_ENTERPRISE ?= true
BUILD_ENTERPRISE_READY = false
BUILD_TYPE_NAME = team
ifneq ($(wildcard $(BUILD_ENTERPRISE_DIR)/.),)
	ifeq ($(BUILD_ENTERPRISE),true)
		BUILD_ENTERPRISE_READY = true
		BUILD_TYPE_NAME = enterprise
	else
		BUILD_ENTERPRISE_READY = false
		BUILD_TYPE_NAME = team
	endif
else
	BUILD_ENTERPRISE_READY = false
	BUILD_TYPE_NAME = team
endif
BUILD_WEBAPP_DIR = ./webapp

# Golang Flags
GOPATH ?= $(GOPATH:)
GOFLAGS ?= $(GOFLAGS:)
GO=$(GOPATH)/bin/godep go
GO_LINKER_FLAGS ?= -ldflags \
				   "-X github.com/dotcominternet/platform/model.BuildNumber=$(BUILD_NUMBER)\
				    -X 'github.com/dotcominternet/platform/model.BuildDate=$(BUILD_DATE)'\
				    -X github.com/dotcominternet/platform/model.BuildHash=$(BUILD_HASH)\
				    -X github.com/dotcominternet/platform/model.BuildEnterpriseReady=$(BUILD_ENTERPRISE_READY)"

# Output paths
DIST_ROOT=dist
DIST_PATH=$(DIST_ROOT)/mattermost

# Tests
TESTS=.

all: dist

dist: | check-style test package

start-docker:
	@echo Starting docker containers

	@if [ $(shell docker ps -a | grep -ci mattermost-mysql) -eq 0 ]; then \
		echo starting mattermost-mysql; \
		docker run --name mattermost-mysql -p 3306:3306 -e MYSQL_ROOT_PASSWORD=mostest \
		-e MYSQL_USER=mmuser -e MYSQL_PASSWORD=mostest -e MYSQL_DATABASE=mattermost_test -d mysql:5.7 > /dev/null; \
	elif [ $(shell docker ps | grep -ci mattermost-mysql) -eq 0 ]; then \
		echo restarting mattermost-mysql; \
		docker start mattermost-mysql > /dev/null; \
	fi

	@if [ $(shell docker ps -a | grep -ci mattermost-postgres) -eq 0 ]; then \
		echo starting mattermost-postgres; \
		docker run --name mattermost-postgres -p 5432:5432 -e POSTGRES_USER=mmuser -e POSTGRES_PASSWORD=mostest \
		-d postgres:9.4 > /dev/null; \
		sleep 10; \
	elif [ $(shell docker ps | grep -ci mattermost-postgres) -eq 0 ]; then \
		echo restarting mattermost-postgres; \
		docker start mattermost-postgres > /dev/null; \
		sleep 10; \
	fi

stop-docker:
	@echo Stopping docker containers

	@if [ $(shell docker ps -a | grep -ci mattermost-mysql) -eq 1 ]; then \
		echo stopping mattermost-mysql; \
		docker stop mattermost-mysql > /dev/null; \
	fi

	@if [ $(shell docker ps -a | grep -ci mattermost-postgres) -eq 1 ]; then \
		echo stopping mattermost-postgres; \
		docker stop mattermost-postgres > /dev/null; \
	fi

clean-docker:
	@echo Removing docker containers

	@if [ $(shell docker ps -a | grep -ci mattermost-mysql) -eq 1 ]; then \
		echo stopping mattermost-mysql; \
		docker stop mattermost-mysql > /dev/null; \
		docker rm -v mattermost-mysql > /dev/null; \
	fi

	@if [ $(shell docker ps -a | grep -ci mattermost-postgres) -eq 1 ]; then \
		echo stopping mattermost-postgres; \
		docker stop mattermost-postgres > /dev/null; \
		docker rm -v mattermost-postgres > /dev/null; \
	fi

check-style:
	@echo Running GOFMT
	$(eval GOFMT_OUTPUT := $(shell gofmt -d -s api/ model/ store/ utils/ manualtesting/ einterfaces/ mattermost.go 2>&1))
	@echo "$(GOFMT_OUTPUT)"
	@if [ ! "$(GOFMT_OUTPUT)" ]; then \
		echo "gofmt sucess"; \
	else \
		echo "gofmt failure"; \
		exit 1; \
	fi

test: start-docker
	$(GO) test $(GOFLAGS) -run=$(TESTS) -test.v -test.timeout=180s ./api || exit 1
	$(GO) test $(GOFLAGS) -run=$(TESTS) -test.v -test.timeout=12s ./model || exit 1
	$(GO) test $(GOFLAGS) -run=$(TESTS) -test.v -test.timeout=120s ./store || exit 1
	$(GO) test $(GOFLAGS) -run=$(TESTS) -test.v -test.timeout=120s ./utils || exit 1
	$(GO) test $(GOFLAGS) -run=$(TESTS) -test.v -test.timeout=120s ./web || exit 1

.prebuild:
	@echo Preparation for running go code
	go get $(GOFLAGS) github.com/tools/godep

	touch $@

prepare-enterprise:
ifeq ($(BUILD_ENTERPRISE_READY),true)
	@echo Enterprise build selected, perparing
	cp $(BUILD_ENTERPRISE_DIR)/imports.go .
endif

build-linux: .prebuild prepare-enterprise
	@echo Build Linux amd64
	env GOOS=linux GOARCH=amd64 $(GO) install $(GOFLAGS) $(GO_LINKER_FLAGS) ./...

build-osx: .prebuild prepare-enterprise
	@echo Build OSX amd64
	env GOOS=darwin GOARCH=amd64 $(GO) install $(GOFLAGS) $(GO_LINKER_FLAGS) ./...

build-windows: .prebuild prepare-enterprise
	@echo Build Windows amd64
	env GOOS=windows GOARCH=amd64 $(GO) install $(GOFLAGS) $(GO_LINKER_FLAGS) ./...

build: build-linux build-windows build-osx

build-client:
	@echo Building mattermost web app

	cd $(BUILD_WEBAPP_DIR) && $(MAKE) build


package: build build-client
	@ echo Packaging mattermost

	@# Remove any old files
	rm -Rf $(DIST_ROOT)

	@# Create needed directories
	mkdir -p $(DIST_PATH)/bin
	mkdir -p $(DIST_PATH)/logs

	@# Resource directories
	cp -RL config $(DIST_PATH)
	cp -RL fonts $(DIST_PATH)
	cp -RL templates $(DIST_PATH)
	cp -RL i18n $(DIST_PATH)

	@# Package webapp
	mkdir -p $(DIST_PATH)/webapp/dist
	cp -RL $(BUILD_WEBAPP_DIR)/dist $(DIST_PATH)/webapp
	mv $(DIST_PATH)/webapp/dist/bundle.js $(DIST_PATH)/webapp/dist/bundle-$(BUILD_NUMBER).js
	sed -i'.bak' 's|bundle.js|bundle-$(BUILD_NUMBER).js|g' $(DIST_PATH)/webapp/dist/root.html
	rm $(DIST_PATH)/webapp/dist/root.html.bak

	@# Help files
ifeq ($(BUILD_ENTERPRISE_READY),true)
	cp $(BUILD_ENTERPRISE_DIR)/ENTERPRISE-EDITION-LICENSE.txt $(DIST_PATH)
else
	cp build/MIT-COMPILED-LICENSE.md $(DIST_PATH)
endif
	cp NOTICE.txt $(DIST_PATH)
	cp README.md $(DIST_PATH)

	@# ----- PLATFORM SPECIFIC -----

	@# Make osx package
	@# Copy binary
	cp $(GOPATH)/bin/darwin_amd64/platform $(DIST_PATH)/bin
	@# Package
	tar -C dist -czf $(DIST_PATH)-$(BUILD_TYPE_NAME)-osx-amd64.tar.gz mattermost
	@# Cleanup
	rm -f $(DIST_PATH)/bin/platform

	@# Make windows package
	@# Copy binary
	cp $(GOPATH)/bin/windows_amd64/platform.exe $(DIST_PATH)/bin
	@# Package
	tar -C dist -czf $(DIST_PATH)-$(BUILD_TYPE_NAME)-windows-amd64.tar.gz mattermost
	@# Cleanup
	rm -f $(DIST_PATH)/bin/platform.exe

	@# Make linux package
	@# Copy binary
	cp $(GOPATH)/bin/platform $(DIST_PATH)/bin
	@# Package
	tar -C dist -czf $(DIST_PATH)-$(BUILD_TYPE_NAME)-linux-amd64.tar.gz mattermost
	@# Don't cleanup linux package so dev machines will have an unziped linux package avalilable
	@#rm -f $(DIST_PATH)/bin/platform


run-server: prepare-enterprise start-docker
	@echo Running mattermost for development

	mkdir -p $(BUILD_WEBAPP_DIR)/dist/files
	$(GO) run $(GOFLAGS) $(GO_LINKER_FLAGS) *.go &

run-client:
	@echo Running mattermost client for development

	cd $(BUILD_WEBAPP_DIR) && $(MAKE) run

run-client-fullmap:
	@echo Running mattermost client for development with FULL SOURCE MAP

	cd $(BUILD_WEBAPP_DIR) && $(MAKE) run-fullmap

run: run-server run-client

run-fullmap: run-server run-client-fullmap

stop-server:
	@echo Stopping mattermost

	@for PID in $$(ps -ef | grep "[g]o run" | awk '{ print $$2 }'); do \
		echo stopping go $$PID; \
		kill $$PID; \
	done

	@for PID in $$(ps -ef | grep "[g]o-build" | awk '{ print $$2 }'); do \
		echo stopping mattermost $$PID; \
		kill $$PID; \
	done

stop-client:
	@echo Stopping mattermost client

	cd $(BUILD_WEBAPP_DIR) && $(MAKE) stop


stop: stop-server stop-client

restart-server: | stop-server run-server

restart-client: | stop-client run-client

clean: stop-docker
	@echo Cleaning

	rm -Rf $(DIST_ROOT)
	go clean $(GOFLAGS) -i ./...

	cd $(BUILD_WEBAPP_DIR) && $(MAKE) clean

	rm -rf api/data
	rm -rf logs

	rm -rf Godeps/_workspace/pkg/

	rm -f mattermost.log
	rm -f .prepare-go

nuke: clean clean-docker
	@echo BOOM

	rm -rf data

setup-mac:
	echo $$(boot2docker ip 2> /dev/null) dockerhost | sudo tee -a /etc/hosts
