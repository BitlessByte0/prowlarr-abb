# syntax=docker/dockerfile:1

FROM ghcr.io/linuxserver/baseimage-alpine:3.18

# set version label
ARG BUILD_DATE
ARG VERSION
ARG PROWLARR_RELEASE
LABEL build_version="BitlessByte version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="Roxedus,thespad"

# environment settings
ARG PROWLARR_BRANCH="master"
ENV XDG_CONFIG_HOME="/config/xdg"


RUN \
  echo "**** install packages ****" && \
  # Install required packages
  apk add -U --upgrade --no-cache \
    icu-libs \
    sqlite-libs \
    xmlstarlet \ 
    git \ 
    dotnet7-sdk \
    nodejs \
    yarn \ 
    npm && \
  echo "**** install prowlarr ****" && \
  mkdir -p /app/prowlarr/bin && \
  if [ -z ${PROWLARR_RELEASE+x} ]; then \
    PROWLARR_RELEASE=$(curl -sL "https://prowlarr.servarr.com/v1/update/${PROWLARR_BRANCH}/changes?runtime=netcore&os=linuxmusl" \
    | jq -r '.[0].version'); \
  fi && \
  # Get the official code from Prowlarr team
  cd /app/prowlarr/ && \
  git clone -b develop --single-branch https://github.com/Prowlarr/Prowlarr.git && \
  # Update the User-Agent
  cd /app/prowlarr/Prowlarr/src/NzbDrone.Common/Http && \
  sed -i "s+_userAgent .*;+_userAgent = \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36\";+g" UserAgentBuilder.cs && \ 
  sed -i "s+_userAgentSimplified .*;+_userAgentSimplified = \"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36\";+g" UserAgentBuilder.cs && \ 
  cd /app/prowlarr/Prowlarr/src/NzbDrone.Core/Indexers/Definitions && \
  sed -i "/^.*Obsolete.*$/d" AudioBookBay.cs && \
  # Build the application
  cd /app/prowlarr/Prowlarr/ && \
  yarn install && \
  yarn build --env production=false && \
  dotnet msbuild -restore ./src/Prowlarr.sln -p:Configuration=Release -p:Platform=Posix -t:PublishAllRids && \
  # Copy the built application into bin
  cp -r /app/prowlarr/Prowlarr/_output/net6.0/linux-musl-x64/* /app/prowlarr/bin/ && \
  cp -r /app/prowlarr/Prowlarr/_output/UI /app/prowlarr/bin && \
  # Add Versioning Info
  echo -e "UpdateMethod=docker\nBranch=${PROWLARR_BRANCH}\nPackageVersion=${VERSION}\nPackageAuthor=BitlessByte)" > /app/prowlarr/package_info && \
  echo "**** cleanup ****" && \
  dotnet nuget locals all -c && \
  rm -rf \
    /app/prowlarr/Prowlarr \
    /tmp/* \
    /var/tmp/*

# copy local files
COPY root/ /

# ports and volumes
EXPOSE 9696
VOLUME /config