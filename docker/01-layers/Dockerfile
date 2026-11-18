# Every instruction that changes files creates one layer.
FROM alpine:3.24

# Layer: adds one small file.
RUN echo "version 1" > /hello.txt

# Layer: adds a 50 MB file.
RUN dd if=/dev/urandom of=/big.bin bs=1M count=50

# Layer: "deletes" the 50 MB file. The image does NOT get smaller:
# this layer only stores a marker ("whiteout") that hides the file.
RUN rm /big.bin

# Layer: changes a file from a lower layer. The new layer stores a full new copy.
RUN echo "version 2" > /hello.txt

# No layer: metadata only.
CMD ["cat", "/hello.txt"]
