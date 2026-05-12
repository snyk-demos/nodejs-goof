FROM node:18.13.0

RUN mkdir /usr/src/goof
RUN mkdir /tmp/extracted_files
COPY . /usr/src/goof
WORKDIR /usr/src/goof

RUN npm update
RUN npm install
RUN groupadd --system appuser && useradd --system --gid appuser appuser
RUN chown -R appuser:appuser /usr/src/goof
RUN chown -R appuser:appuser /tmp/extracted_files
EXPOSE 3001
EXPOSE 9229
USER appuser
ENTRYPOINT ["npm", "start"]