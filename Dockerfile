# Built with arch: amd64 flavor: xfce4 image: nvidia/cuda:10.1-devel-ubuntu18.04
#
################################################################################
# base system
################################################################################
FROM nvidia/cuda:10.1-devel-ubuntu18.04 as system

COPY ali-source-list18.04 /etc/apt/sources.list

# built-in packages
ENV DEBIAN_FRONTEND noninteractive
RUN apt update \
    && apt install -y --no-install-recommends software-properties-common curl apache2-utils \
    && apt update \
    && apt install -y --no-install-recommends --allow-unauthenticated \
        supervisor nginx sudo net-tools zenity xz-utils \
        dbus-x11 x11-utils alsa-utils \
        mesa-utils libgl1-mesa-dri \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

ENV X11VNC_VERSION=0.9.16-1
# arc-theme
RUN add-apt-repository -y ppa:noobslab/themes

# install debs error if combine together

RUN add-apt-repository -y ppa:fcwu-tw/apps \
    && apt update \
    && apt install -y --no-install-recommends --allow-unauthenticated \
        xvfb x11vnc=$X11VNC_VERSION \
        vim-tiny firefox xfce4-terminal  \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

RUN apt update \
    && apt install -y --no-install-recommends --allow-unauthenticated \
        xubuntu-desktop \
    && apt autoclean -y \
    && apt autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# tini for subreap
ARG TINI_VERSION=v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-amd64 /bin/tini
RUN chmod +x /bin/tini

# ffmpeg
RUN apt update \
    && apt install -y --no-install-recommends --allow-unauthenticated \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir /usr/local/ffmpeg \
    && ln -s /usr/bin/ffmpeg /usr/local/ffmpeg/ffmpeg

# python library for backend
COPY rootfs/usr/local/lib/web/backend/requirements.txt /tmp/
RUN apt-get update \
    && dpkg-query -W -f='${Package}\n' > /tmp/a.txt \
    && apt-get install -y python-pip python-dev build-essential \
	&& pip install setuptools wheel -i https://mirrors.aliyun.com/pypi/simple/ && pip install -r /tmp/requirements.txt -i https://mirrors.aliyun.com/pypi/simple/ \
    && dpkg-query -W -f='${Package}\n' > /tmp/b.txt \
    && apt-get remove -y `diff --changed-group-format='%>' --unchanged-group-format='' /tmp/a.txt /tmp/b.txt | xargs` \
    && apt-get autoclean -y \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/* /tmp/a.txt /tmp/b.txt

## install unqiue dependency
RUN apt-get update && apt-get install -y python3-pip \
                      git \ 
                      vim \
                      openssh-server \
                      language-pack-zh-hans \
                      fonts-wqy-microhei \
                      ttf-wqy-zenhei \
                      chromium-browser \ 
                      python3-venv

################################################################################
# builder
################################################################################
FROM nvidia/cuda:10.1-devel-ubuntu18.04 as builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates gnupg patch

# nodejs
RUN curl -sL https://deb.nodesource.com/setup_12.x | bash - \
    && apt-get install -y nodejs

# yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && apt-get install -y yarn

# build frontend
COPY web /src/web
RUN cd /src/web \
    && npm install chromedriver --chromedriver_cdnurl=http://cdn.npm.taobao.org/dist/chromedriver \
    && mv /src/web/node_modules/chromedriver/lib/chromedriver/chromedriver /src/web/node_modules/chromedriver \
    && yarn \
    && yarn build
RUN sed -i 's#app/locale/#novnc/app/locale/#' /src/web/dist/static/novnc/app/ui.js

################################################################################
# merge
################################################################################
FROM system

COPY --from=builder /src/web/dist/ /usr/local/lib/web/frontend/
COPY rootfs /
RUN ln -sf /usr/local/lib/web/frontend/static/websockify /usr/local/lib/web/frontend/static/novnc/utils/websockify && \
	chmod +x /usr/local/lib/web/frontend/static/websockify/run

EXPOSE 80
WORKDIR /root
ENV HOME=/home/ubuntu \
    SHELL=/bin/bash
HEALTHCHECK --interval=30s --timeout=5s CMD curl --fail http://127.0.0.1:6079/api/health

RUN locale-gen zh_CN.UTF-8 &&\
  DEBIAN_FRONTEND=noninteractive dpkg-reconfigure locales
RUN locale-gen zh_CN.UTF-8  
ENV LANG zh_CN.UTF-8  
ENV LANGUAGE zh_CN:zh  
ENV LC_ALL zh_CN.UTF-8  

ENTRYPOINT ["/startup.sh"]
