# Docker demos

Three short live demos about container images. Each one shows **one idea**.

| Folder | Idea | Time (estimate) |
|---|---|---|
| `01-layers/` | An image is a stack of layers. Deleting a file does not make the image smaller. | 5 min |
| `02-secret-leak/` | `COPY key` + `RUN rm key` leaves the key in the image. How to do it right. | 5 min |
| `03-multistage/` | One Dockerfile, two results: a local-dev image and a small production image (Spring Boot). | 8 min |

## What you need

| Tool | Used for | Install |
|---|---|---|
| Docker Desktop (with Compose) | Everything | [docker.com](https://www.docker.com/products/docker-desktop/) |
| [dive](https://github.com/wagoodman/dive) | Browsing layers | `brew install dive` |
| [hadolint](https://github.com/hadolint/hadolint) | Linting a Dockerfile | `brew install hadolint` |
| [trivy](https://trivy.dev/) | Scanning an image for known vulnerabilities | `brew install trivy` |

## Before the talk

Run this once on good internet. It pulls all base images and builds the Spring Boot demo
(which downloads the Maven dependencies), so the live builds are fast and download nothing big.
Demos 1 and 2 are left unbuilt on purpose, so their first live build is a real one.
(A build still asks the registry whether a base image tag has changed. This was not tested
with no network at all; if the Wi-Fi is down, demo 3 can still be shown from the images
that `warmup.sh` already built.)

```sh
./docker/warmup.sh
```

All commands below are run from the `docker/` folder:

```sh
cd docker
```

> Port 8888 is used for the Spring Boot app. Change it in `03-multistage/compose.yaml`
> and in the `docker run` command if it's taken on your machine.

## Demo 1: layers

Show the Dockerfile first (`01-layers/Dockerfile`), then:

```sh
docker build -t demo-layers 01-layers
docker build -t demo-layers 01-layers      # again: every step is CACHED
docker history demo-layers                 # one row per instruction, with its size
docker run --rm demo-layers ls /big.bin    # "No such file" - the file is gone...
docker images demo-layers                  # ...but the image still carries its 50 MB
```

Now look inside:

```sh
dive demo-layers
```

- Left side: the layers. Right side: the files of the selected layer.
- `Tab` switches sides. The bar at the bottom lists the other keys; hiding unmodified files is the useful one.
- Select the `dd` layer: `big.bin` is added. Select the `rm` layer: `big.bin` is marked as removed, but the layer above still holds it.
- Bottom left: dive reports about 52 MB of "wasted space".

No magic, without dive: an image is just tar files.

```sh
mkdir -p /tmp/layers
docker save demo-layers | tar -x -C /tmp/layers
ls -la /tmp/layers/blobs/sha256            # every layer is one file; the 50 MB one is easy to spot
for l in /tmp/layers/blobs/sha256/*; do tar -tvf $l 2>/dev/null | grep -E "big.bin|hello.txt"; done
```

You'll see `hello.txt` twice (two full copies), `big.bin` (50 MB) and `.wh.big.bin`.
That last one is the "whiteout" marker: it only hides `big.bin`, it does not delete it.

**Say:** layers are read-only and only ever added. To really remove something, never put it
in a layer: do the create and the delete in the **same** `RUN`, or use a multi-stage build.

## Demo 2: the deleted key that is still there

Show `02-secret-leak/Dockerfile`: `COPY key.private`, use it, `RUN rm key.private`.

```sh
docker build -t demo-leak 02-secret-leak
docker run --rm demo-leak                  # lists /app: no key.private. Looks safe.
docker history demo-leak                   # but the COPY layer is still part of the image
```

Get the key back. Anyone who can pull the image can do this:

```sh
mkdir -p /tmp/leak
docker save demo-leak | tar -x -C /tmp/leak
for l in /tmp/leak/blobs/sha256/*; do tar -xOf $l app/key.private 2>/dev/null; done
```

The key is printed. (Visual version: `dive demo-leak`, select the `COPY` layer, the file is there.)

The fix is a build secret (`02-secret-leak/Dockerfile.fixed`). The key is mounted only
while one `RUN` executes and is never written to a layer:

```sh
docker build -t demo-fixed -f 02-secret-leak/Dockerfile.fixed --secret id=key,src=02-secret-leak/key.private 02-secret-leak
docker run --rm demo-fixed                 # fingerprint.txt exists, so the key was used

rm -rf /tmp/leak && mkdir -p /tmp/leak
docker save demo-fixed | tar -x -C /tmp/leak
for l in /tmp/leak/blobs/sha256/*; do tar -xOf $l app/key.private 2>/dev/null; done    # prints nothing
```

**Say:** `ARG` and `ENV` are not safe either (they show up in `docker history`). If a secret
was ever pushed inside an image, treat it as leaked and rotate it.

> `key.private` in this repo is a fake demo value.

## Demo 3: multi-stage build (Spring Boot)

Show `03-multistage/Dockerfile`. Four stages:

| Stage | Based on | Contains |
|---|---|---|
| `base` | Maven + JDK | `pom.xml` and all downloaded dependencies |
| `localdev` | `base` | Nothing more. The source code is mounted from your laptop. |
| `build` | `base` | Source code and the built jar |
| `final` | JRE only | Just the jar, running as a non-root user |

### Local development

`compose.yaml` builds only up to the `localdev` stage (`target: localdev`):

```sh
cd 03-multistage
docker compose up --build --watch
```

In a second terminal:

```sh
curl localhost:8888                        # Hello from a container! Running as user: root
```

Now edit the text in `src/main/java/com/example/demo/DemoApplication.java` and save.
Compose sees the change and restarts the app (a few seconds). `curl` again: new text.

Stop it with `Ctrl+C`, then `docker compose down`.

### Production image

```sh
docker build -t demo-app:final .           # no --target: builds the last stage
docker run -d --rm --name demo-app -p 8888:8080 demo-app:final
curl localhost:8888                        # ...Running as user: app
```

Compare the two images built from the same Dockerfile:

```sh
docker images demo-app                     # final is about half the size of localdev
docker run --rm --entrypoint sh demo-app:final -c "id; which mvn javac"    # uid 10001, no Maven, no compiler
```

Two quick checks you'd run in CI:

```sh
hadolint Dockerfile                        # lint: no output = clean (try ../01-layers/Dockerfile for findings)
trivy image --severity HIGH,CRITICAL --skip-db-update --skip-java-db-update demo-app:final
```

The two `--skip-...` flags make trivy use the databases that `warmup.sh` downloaded, so the
scan needs no internet. Drop `--severity` to see the full list.

Cache: change the text in `DemoApplication.java` again and rebuild. The dependency
step (`mvn dependency:go-offline`) is `CACHED`; only the `build` stage runs again.

```sh
docker build -t demo-app:final .
docker stop demo-app
cd ..
```

**Say:** build tools, source code and the JDK never reach production. Smaller image,
fewer things to patch, fewer things for an attacker to use.

## Clean up

```sh
docker rmi demo-layers demo-leak demo-fixed demo-app:localdev demo-app:final 03-multistage-app
rm -rf /tmp/layers /tmp/leak
```
