FROM mcr.microsoft.com/azure-cli:2.72.0

RUN curl -LO "https://dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl" \
    && install -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl

CMD ["/bin/sh"]
