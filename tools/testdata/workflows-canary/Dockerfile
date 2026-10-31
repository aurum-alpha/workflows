# The image ci.yml's workflows-canary jobs build through the real
# job-image-build and start through the real job-image-starts, so both
# reusable jobs run end to end in the catalog's own CI. A RUN step, so a build
# on the farm and a local one do the same work; a COPY, so the context reaches
# the builder; a port, so job-image-starts has something to probe.
FROM busybox:1.37.0
RUN mkdir -p /www && echo "built by workflows-canary" > /www/index.html
COPY Dockerfile /www/Dockerfile.txt
EXPOSE 5000
CMD ["httpd", "-f", "-p", "5000", "-h", "/www"]
