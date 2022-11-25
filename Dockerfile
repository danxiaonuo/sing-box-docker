##########################################
#         构建可执行二进制文件             #
##########################################
# 指定构建的基础镜像
# FROM golang:alpine AS builder
FROM alpine:latest AS builder

# 作者描述信息
MAINTAINER danxiaonuo
# 时区设置
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
# 语言设置
ARG LANG=C.UTF-8
ENV LANG=$LANG

# GO环境变量
ARG GOLANG_VERSION=1.19.3
ENV GOLANG_VERSION=$GOLANG_VERSION
ARG GOPROXY=""
ENV GOPROXY ${GOPROXY}
ARG GO111MODULE=on
ENV GO111MODULE=$GO111MODULE
ARG CGO_ENABLED=1
ENV CGO_ENABLED=$CGO_ENABLED
ARG GOROOT=/usr/local/go
ENV GOROOT=$GOROOT
ARG GOPATH=/go
ENV GOPATH=$GOPATH
ENV PATH=$PATH:$GOROOT/bin:$GOPATH/bin

# 源文件下载路径
ARG DOWNLOAD_SRC=/tmp/src
ENV DOWNLOAD_SRC=$DOWNLOAD_SRC

# SINGBOX版本
ARG SINGBOX_VERSION=1.1-beta17
ENV SINGBOX_VERSION=$SINGBOX_VERSION

ARG BUILD_DEPS="go"
ENV BUILD_DEPS=$BUILD_DEPS

ARG PKG_DEPS="\
      bash \
      gcc \
      musl-dev \
      git \
      linux-headers \
      build-base \
      zlib-dev \
      openssl \
      openssl-dev \
      tor \
      libevent-dev \
      tzdata \
      ca-certificates"
ENV PKG_DEPS=$PKG_DEPS

# ***** 安装依赖并构建二进制文件 *****
RUN set -eux && \
   # 修改源地址
   sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
   # 更新源地址并更新系统软件
   apk update && apk upgrade && \
   # 安装依赖包
   apk add --no-cache --clean-protected $BUILD_DEPS && \
   apk add --no-cache --clean-protected $PKG_DEPS && \
   rm -rf /var/cache/apk/* && \
   # 更新时区
   ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
   # 更新时间
   echo ${TZ} > /etc/timezone && \
   # 安装GO环境
   mkdir -p "$GOPATH/src" "$GOPATH/bin" "$DOWNLOAD_SRC" && chmod -R 777 "$GOPATH" && \
   wget --no-check-certificate https://dl.google.com/go/go${GOLANG_VERSION}.src.tar.gz \
    -O ${DOWNLOAD_SRC}/go${GOLANG_VERSION}.src.tar.gz && \
   cd ${DOWNLOAD_SRC} && tar xvf go${GOLANG_VERSION}.src.tar.gz -C ${DOWNLOAD_SRC} && \
   export GOCACHE='/tmp/gocache' && cd ${DOWNLOAD_SRC}/go/src && \
   export GOAMD64='v1' GOARCH='amd64' GOOS='linux' && \
   export GOROOT_BOOTSTRAP="$(go env GOROOT)" GOHOSTOS="$GOOS" GOHOSTARCH="$GOARCH" && ./make.bash && \
   apk del --no-network $BUILD_DEPS && \
   # 克隆源码运行安装
   git clone --depth=1 -b $SINGBOX_VERSION --progress https://github.com/SagerNet/sing-box.git /src && \
   cd /src && export COMMIT=$(git rev-parse --short HEAD) && \
   go env -w GO111MODULE=on && \
   go env -w CGO_ENABLED=1 && \
   go env && \
   go mod tidy && \
   go build -v -trimpath -tags 'with_quic,with_grpc,with_wireguard,with_shadowsocksr,with_ech,with_utls,with_acme,with_clash_api,with_gvisor,with_embedded_tor,with_lwip' \
        -o /go/bin/sing-box \
        -ldflags "-X github.com/sagernet/sing-box/constant.Commit=${COMMIT} -w -s -buildid=" \
        ./cmd/sing-box

##########################################
#         构建基础镜像                    #
##########################################
# 
# 指定创建的基础镜像
FROM alpine:latest

# 作者描述信息
MAINTAINER danxiaonuo
# 时区设置
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
# 语言设置
ARG LANG=C.UTF-8
ENV LANG=$LANG

ARG PKG_DEPS="\
      zsh \
      bash \
      bash-doc \
      bash-completion \
      linux-headers \
      build-base \
      zlib-dev \
      openssl \
      openssl-dev \
      tor \
      libevent-dev \
      bind-tools \
      iproute2 \
      ipset \
      git \
      vim \
      tzdata \
      curl \
      wget \
      lsof \
      zip \
      unzip \
      supervisor \
      ca-certificates"
ENV PKG_DEPS=$PKG_DEPS

# ***** 安装依赖 *****
RUN set -eux && \
   # 修改源地址
   sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
   # 更新源地址并更新系统软件
   apk update && apk upgrade && \
   # 安装依赖包
   apk add --no-cache --clean-protected $PKG_DEPS && \
   rm -rf /var/cache/apk/* && \
   # 更新时区
   ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
   # 更新时间
   echo ${TZ} > /etc/timezone && \
   # 更改为zsh
   sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true && \
   sed -i -e "s/bin\/ash/bin\/zsh/" /etc/passwd && \
   sed -i -e 's/mouse=/mouse-=/g' /usr/share/vim/vim*/defaults.vim && \
   /bin/zsh
   
# 拷贝sing-box
COPY --from=builder /go/bin/sing-box /usr/bin/sing-box

# 环境变量
ENV PATH /usr/bin/sing-box:$PATH
 
# 授予文件权限
RUN set -eux && \
    mkdir -p /etc/sing-box && \
    chmod +x /usr/bin/sing-box
    
# 拷贝文件
COPY ["./conf/sing-box", "/etc/sing-box"]
COPY ["./conf/supervisor", "/etc/supervisor"]

# 容器信号处理
STOPSIGNAL SIGQUIT

# 运行命令
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
