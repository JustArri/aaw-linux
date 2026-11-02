# AAW Linux

This repository is a minimal Buildroot external tree for building a dedicated
Arri's Audio Workstation appliance image. It currently supports Raspberry Pi 5;
board-specific files live under `rpi5/` so support for other boards can be added
without duplicating the common AAW package and audio configuration.

The image includes AAW with its embedded web interface, PipeWire and
WirePlumber, wired DHCP, a standalone Wi-Fi access point, SSH/SFTP, automatic
root filesystem expansion, and system power controls. WirePlumber runs
statelessly and initializes detected output devices to 100% system volume.

## Host requirements

Use a Linux build host. Install the normal Buildroot prerequisites plus Git,
Rust, Bun, Clang, CMake, and development tools. On Debian or Ubuntu, start with:

```sh
sudo apt install build-essential git curl file rsync bc cpio unzip wget \
    python3 patch perl tar gzip bzip2 xz-utils clang libclang-dev cmake \
    pkg-config libasound2-dev libsndfile1-dev libpipewire-0.3-dev
```

Install current Rust and Bun using their upstream instructions if they are not
already available.

## Obtain the sources

Clone this repository, then clone AAW—including its native submodules—into the
reserved `aaw/` directory:

```sh
git clone https://github.com/JustArri/aaw-linux
cd aaw-linux
git clone --recurse-submodules https://github.com/JustArri/aaw.git aaw
```

Download the Buildroot release used by the configuration:

```sh
curl -LO https://buildroot.org/downloads/buildroot-2026.08.tar.xz
tar -xf buildroot-2026.08.tar.xz
mv buildroot-2026.08 buildroot
```

## Configure credentials

The development defaults are deliberately simple:

- Wi-Fi network: `AAW`
- Wi-Fi password: `aaw-wifi`
- root password: `aaw`

Change the Wi-Fi country, SSID, and passphrase in
`rpi5/rootfs-overlay/etc/hostapd.conf`. Change the root password by editing
`BR2_TARGET_GENERIC_ROOT_PASSWD` in `rpi5/defconfig`. Do this before exposing
the appliance to an untrusted network.

Open the Wi-Fi configuration in your preferred editor:

```sh
${EDITOR:-nano} rpi5/rootfs-overlay/etc/hostapd.conf
```

Set `country_code` to the applicable two-letter ISO country code. Choose the
SSID freely; a WPA2 passphrase must contain between 8 and 63 characters. For
example, these commands select the United States, rename the network, and set a
new development password:

```sh
sed -i \
    -e 's/^country_code=.*/country_code=US/' \
    -e 's/^ssid=.*/ssid=My-AAW/' \
    -e 's/^wpa_passphrase=.*/wpa_passphrase=choose-a-strong-password/' \
    rpi5/rootfs-overlay/etc/hostapd.conf
```

Verify the resulting non-comment settings:

```sh
grep -E '^(country_code|ssid|wpa_passphrase)=' \
    rpi5/rootfs-overlay/etc/hostapd.conf
```

The root password can be changed directly in the tracked defconfig:

```sh
${EDITOR:-nano} rpi5/defconfig
grep '^BR2_TARGET_GENERIC_ROOT_PASSWD=' rpi5/defconfig
```

Alternatively, after creating the Buildroot output directory in the next
section, open Buildroot's configuration interface:

```sh
make -C output/rpi5 menuconfig
```

Navigate to:

```text
System configuration  --->
    Root password
```

Exit and save the configuration, then export the result back to the tracked
Raspberry Pi 5 defconfig:

```sh
make -C output/rpi5 savedefconfig \
    BR2_DEFCONFIG="$PWD/rpi5/defconfig"
```

Review `rpi5/defconfig` before committing it. The password is stored in this
configuration, so do not publish a private production password in a public
repository.

## Configure Buildroot

Create an out-of-tree Raspberry Pi 5 build directory:

```sh
make -C buildroot \
    O="$PWD/output/rpi5" \
    BR2_EXTERNAL="$PWD" \
    BR2_DEFCONFIG="$PWD/rpi5/defconfig" \
    defconfig
```

## Build the embedded frontend

AAW embeds the statically generated SvelteKit frontend in its Rust binary:

```sh
cd aaw/frontend
bun install --frozen-lockfile
bun run build
cd ../..
```

## Prepare Rust dependencies

Buildroot builds Cargo packages offline. Copy the local AAW tree into its build
directory, install Buildroot's host Rust toolchain, and vendor the locked
dependency set:

```sh
make -C output/rpi5 aaw-dirclean
make -C output/rpi5 source -j"$(nproc)"
make -C output/rpi5 aaw-rsync
make -C output/rpi5 host-rustc -j"$(nproc)"

AAW_LINUX_DIR="$PWD"
mkdir -p output/rpi5/build/aaw-0.1.0/.cargo
cd output/rpi5/build/aaw-0.1.0
CARGO_HOME="$AAW_LINUX_DIR/buildroot/dl/br-cargo-home" \
    "$AAW_LINUX_DIR/output/rpi5/host/bin/cargo" \
    vendor --locked VENDOR > .cargo/config.toml
cd "$AAW_LINUX_DIR"
```

## Build the image

```sh
make -C output/rpi5 -j"$(nproc)"
ls -lh output/rpi5/images/sdcard.img
```

The initial build downloads and compiles the complete Linux toolchain and may
take a long time.

## Write the image to a storage device

The image can be written to any storage device that the Raspberry Pi can boot
from, including an SD card, USB storage, or an NVMe device. Identify the
destination and its mounted partitions:

```sh
lsblk -p -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL
```

Replace the deliberately invalid placeholders below with the actual partition
and whole-device paths. Unmount every mounted partition belonging to the
destination, then write to the whole device—not to one of its partitions.
Using the wrong device destroys its contents.

```sh
sudo umount /dev/DEVICE_PARTITION_1 /dev/DEVICE_PARTITION_2
sudo dd \
    if=output/rpi5/images/sdcard.img \
    of=/dev/WHOLE_DEVICE \
    bs=16M \
    conv=fsync \
    status=progress
sync
```

Optionally verify the written bytes:

```sh
sudo cmp \
    -n "$(stat -c %s output/rpi5/images/sdcard.img)" \
    output/rpi5/images/sdcard.img \
    /dev/WHOLE_DEVICE
```

On first boot, the root partition expands to fill the storage device. Ethernet
obtains an IPv4 address through DHCP. The device also provides the `AAW` Wi-Fi
network and is reachable from that network at `http://aaw.home.arpa/` or
`http://10.0.0.1/`.

## Rebuild after changing AAW

Rebuild the frontend first when it changed. Then synchronize and rebuild the
AAW package:

```sh
cd aaw/frontend
bun run build
cd ../..

make -C output/rpi5 aaw-rsync
make -C output/rpi5 aaw-rebuild -j"$(nproc)"
```

Run a normal top-level build when you need an updated disk image:

```sh
make -C output/rpi5 -j"$(nproc)"
```

After changes to `Cargo.lock`, repeat the vendoring step. Use
`aaw-dirclean` only when a clean AAW package rebuild is actually required.

## Update AAW on a running appliance

For an AAW-only update, the complete SD-card image does not need to be
reflashed. Build the current frontend and cross-compiled binary as described
above, then transfer the binary over SFTP with `scp`:

```sh
scp output/rpi5/target/usr/bin/aaw root@aaw.home.arpa:/tmp/aaw
```

Install the uploaded binary and restart the service:

```sh
ssh root@aaw.home.arpa \
    'chmod 0755 /tmp/aaw && \
     systemctl stop aaw && \
     install -m 0755 /tmp/aaw /usr/bin/aaw && \
     rm /tmp/aaw && \
     systemctl start aaw'
```

Confirm that the new process started successfully:

```sh
ssh root@aaw.home.arpa 'systemctl --no-pager --full status aaw'
ssh root@aaw.home.arpa 'journalctl -u aaw -n 100 --no-pager'
```

Replace `aaw.home.arpa` with the appliance's Ethernet address when the hostname
is not available. Project and asset data under `/var/lib/aaw` are not replaced
by this procedure.

Rebuild and write the generated disk image (`sdcard.img`) again when changing
Buildroot packages, the kernel, system services, root filesystem overlays,
PipeWire/WirePlumber policy, or other operating-system configuration.

