FROM node:22-bookworm-slim

RUN npm install --location=global @actual-app/cli@26.7.0 \
    && npm cache clean --force

USER node
ENTRYPOINT ["actual"]