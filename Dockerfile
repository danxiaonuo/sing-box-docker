##########################################
#         构建可执行二进制文件             #
##########################################
# 指定构建的基础镜像
FROM golang:alpine AS builder

# 作者描述信息
MAINTAINER danxiaonuo
# 时区设置
ARG TZ=Asia/Shanghai
ENV TZ=$TZ
# 语言设置
ARG LANG=C.UTF-8
ENV LANG=$LANG

# GO环境变量
ARG GOPROXY=""
ENV GOPROXY ${GOPROXY}
ARG GO111MODULE=on
ENV GO111MODULE=$GO111MODULE
ARG CGO_ENABLED=1
ENV CGO_ENABLED=$CGO_ENABLED

# SINGBOX版本
ARG SINGBOX_VERSION=1.1-beta17
ENV SINGBOX_VERSION=$SINGBOX_VERSION

ARG PKG_DEPS="\
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
   apk add --no-cache --clean-protected $PKG_DEPS && \
   rm -rf /var/cache/apk/* && \
   # 更新时区
   ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && \
   # 更新时间
   echo ${TZ} > /etc/timezone && \
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
