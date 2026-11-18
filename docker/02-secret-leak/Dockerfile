# BAD: the key is deleted, but it stays in the image forever.
FROM alpine:3.24
WORKDIR /app

# Layer 1: the key is now part of the image.
COPY key.private .

# Layer 2: use the key (a stand-in for "git clone a private repo", "npm login", ...).
RUN sha256sum key.private > fingerprint.txt

# Layer 3: hides the key. Layer 1 still contains it.
RUN rm key.private

CMD ["ls", "-la", "/app"]
