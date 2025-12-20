FROM ubuntu:24.04 AS builder
RUN apt update
RUN apt install -y build-essential git clang pkg-config bison flex libreadline-dev tcl-dev

WORKDIR /root/yosys
COPY . .
RUN make config-clang
RUN make
RUN make install

FROM ubuntu:24.04
RUN apt update
RUN apt install -y libreadline-dev tcl-dev
RUN apt autoclean && apt clean && apt -y autoremove
RUN rm -rf /var/lib/apt/lists
COPY --from=builder /usr/local/bin/yosys* /usr/local/bin/
ENTRYPOINT ["yosys"]
