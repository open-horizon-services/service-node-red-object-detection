FROM registry.access.redhat.com/ubi9:9.1.0-1646 as build
LABEL stage=builder

RUN dnf install --nodocs -y nodejs nodejs-nodemon npm --setopt=install_weak_deps=0 --disableplugin=subscription-manager \
    && dnf install --nodocs -y make gcc gcc-c++  --setopt=install_weak_deps=0 --disableplugin=subscription-manager \
    && dnf clean all --disableplugin=subscription-manager

RUN mkdir -p /opt/app-root/data
WORKDIR /opt/app-root/data
COPY ./package.json /opt/app-root/data/package.json
# Prevent "npm ERR! code ERR_SOCKET_TIMEOUT" by upgrading from npm 8.3 to >= npm 8.5.1
RUN npm install --no-audit --no-update-notifier --no-fund --omit=dev --omit=optional --location=global npm@8.19.2
RUN npm install --no-audit --no-update-notifier --no-fund --omit=dev

COPY ./settings.js /opt/app-root/data/
COPY ./flow.json /opt/app-root/data/flows.json
COPY ./flow_cred.json /opt/app-root/data/flows_cred.json
COPY ./screenshots/apple-keyboard-ccby40.jpg /opt/app-root/data/apple-keyboard-ccby40.jpg

# Set permissions so that users can use Node-RED "Manage Palette" to add packages
RUN chown -R 1000:1000 .

## Release image
FROM registry.access.redhat.com/ubi9/nodejs-18-minimal:1-18

USER 0
RUN microdnf update -y --nodocs --disableplugin=subscription-manager --setopt=install_weak_deps=0 && \
    microdnf clean all && \
    rm -rf /mnt/rootfs/var/cache/* /mnt/rootfs/var/log/dnf* /mnt/rootfs/var/log/yum.*

RUN mkdir -p /opt/app-root/data && chown 1000 /opt/app-root/data
USER 1000
COPY --from=build /opt/app-root/data /opt/app-root/data/
WORKDIR /opt/app-root/data

ENV PORT 1880
ENV NODE_ENV=production
ENV NODE_PATH=/opt/app-root/data/node_modules
EXPOSE 1880

CMD ["node", "/opt/app-root/data/node_modules/node-red/red.js", "--setting", "/opt/app-root/data/settings.js", "/opt/app-root/data/flows.json"]
