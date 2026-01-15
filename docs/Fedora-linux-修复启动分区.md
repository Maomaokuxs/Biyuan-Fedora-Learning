
# 0.说明

- 不建议使用grub2-install命令，如下:

```bash
grub2-install --target=x86_64-efi --efi-directory=/boot/efi --force
```

- 因为：

Fedora 使用 Shim 和 GRUB 的组合来支持 UEFI Secure Boot，直接使用 grub2-install 会绕过 Secure Boot 安全机制，UEFI 系统有完全不同的引导管理方式。
# 1.挂载分区（根据你的实际情况调整设备名）

- 一般情况

```bash
mount /dev/sda2 /mnt  # 根分区
mount /dev/sda1 /mnt/boot/efi  # EFI 分区
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run
mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars
```

- 对于使用了btrfs文件系统并创建了btrfs子卷

```bash
mount -o subvol=/@ /dev/sda2/ /mnt  # 根分区
mount -o subvol=/@home /dev/sda2 /mnt/home
mount /dev/sda1 /mnt/boot/efi  # EFI 分区
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run
mount --bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars
```

# 2.然后 chroot

``` bash
 chroot /mnt
```

# 3. 清理可能损坏的配置

```bash
rm -rf /boot/efi/EFI/fedora/
```

# 4. 重新安装所有引导组件

```bash
dnf reinstall kernel-core shim grub2-efi grub2-common
```

# 5. 重新生成 initramfs

```bash
dracut --force
```

# 6. 重新生成 GRUB 配置（这个命令在 UEFI 系统中是安全的）

```bash
grub2-mkconfig -o /boot/grub2/grub.cfg
```

# 7. 验证文件

```bash
# 1. 检查 EFI 文件
ls -la /boot/efi/EFI/fedora/
# 应该看到：shimx64.efi, grubx64.efi, mmx64.efi

# 2. 检查 GRUB 配置
ls -la /boot/grub2/grub.cfg

# 3. 检查内核文件
ls -la /boot/vmlinuz-* /boot/initramfs-*

# 4. 检查 UEFI 启动项（在 Live 环境中）
efibootmgr -v
```

