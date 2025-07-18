# syntax=docker/dockerfile:1
FROM alpine:latest AS builder

ENV XDG_CONFIG_HOME="/config/xdg"

ARG BUILD_DATE
ARG VERSION

# Prowlarr RID options:
#   win-x64
#   win-x86
#   linux-x64
#   linux-musl-x64
#   linux-arm64
#   linux-musl-arm64
#   linux-arm
#   linux-musl-arm
#   osx-x64
#   osx-arm64
ARG RID="linux-musl-x64"
ARG PROWLARR_BRANCH="master"

LABEL build_version="BitlessByte version:- ${VERSION} Build-date:- ${BUILD_DATE}" \
      build_date=$BUILD_DATE \
      version=$VERSION \
      maintainer="BitlessByte"

## STAGE 1
## BUILD THE APPLICATION

# Install Dependencies
RUN apk update && apk add -U --upgrade --no-cache \
    git curl bash build-base \
    nodejs yarn npm jq \
    wget icu-libs sqlite-libs xmlstarlet

# Download Prowlarr from GitHub
RUN mkdir -p /app/prowlarr/bin && \
    git clone -b ${PROWLARR_BRANCH} --single-branch https://github.com/Prowlarr/Prowlarr.git /tmp/Prowlarr

# Install dotnet with the version specified by Prowlarr
RUN export DOTNET_SDK_VERSION=$(jq -r '.sdk.version' /tmp/Prowlarr/global.json) && \
    export DOTNET_SDK_VERSION=${DOTNET_SDK_VERSION:-6.0.428} && \
    echo ${DOTNET_SDK_VERSION} > /tmp/dotnet_version && \
    wget https://dotnetcli.azureedge.net/dotnet/Sdk/${DOTNET_SDK_VERSION}/dotnet-sdk-${DOTNET_SDK_VERSION}-${RID}.tar.gz && \
    mkdir -p /usr/share/dotnet && \
    tar -zxf dotnet-sdk-${DOTNET_SDK_VERSION}-${RID}.tar.gz -C /usr/share/dotnet && \
    ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet

# Update the User-Agent
RUN cd /tmp/Prowlarr/src/NzbDrone.Common/Http && \
    sed -i "s+_userAgent .*;+_userAgent = \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36\";+g" UserAgentBuilder.cs && \
    sed -i "s+_userAgentSimplified .*;+_userAgentSimplified = \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36\";+g" UserAgentBuilder.cs

# Copy custom indexers into Prowlarr
COPY custom_indexers/* /tmp/Prowlarr/src/NzbDrone.Core/Indexers/Definitions/

# Build Prowlarr
RUN export DOTNET_SDK_VERSION=$(cat /tmp/dotnet_version) && \
    export DOTNET_SDK_MAJOR_VERSION=${DOTNET_SDK_VERSION%%.*} && \
    if [ -z "$DOTNET_SDK_MAJOR_VERSION" ]; then \
        export DOTNET_SDK_MAJOR_VERSION=6; \
    fi && \
    cd /tmp/Prowlarr && \
    chmod +x build.sh && \
    # Build Prowlarr
    ./build.sh --backend --frontend --packages -f net${DOTNET_SDK_MAJOR_VERSION}.0 -r ${RID} && \
    cp -r _output/net${DOTNET_SDK_MAJOR_VERSION}.0/${RID}/publish/* /app/prowlarr/bin/ && \
    cp -r _output/UI /app/prowlarr/bin && \
    echo -e "UpdateMethod=docker\nBranch=${PROWLARR_BRANCH}\nPackageVersion=${VERSION}\nPackageAuthor=BitlessByte" > /app/prowlarr/package_info

## STAGE 2
## PACKAGE THE IMAGE

FROM ghcr.io/linuxserver/baseimage-alpine:3.22 AS final

RUN apk add -U --upgrade --no-cache \
    icu-libs \
    sqlite-libs \
    xmlstarlet

COPY root/ /
COPY --from=builder /app /app
RUN echo "$(ls -al /app)"

ENV TZ=UTC \
    LANG=en_US.UTF-8

EXPOSE 9696
VOLUME /config

