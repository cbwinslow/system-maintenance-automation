# Multi-Drive LVM Storage Pool Plan

## Current Drive Inventory

| Drive | Model | Size | Current Status | Usage |
|-------|-------|------|----------------|--------|
| **sda** | WDC WD20EARZ-00C | 2TB | FAT32 (CBWHDD) | 72GB data (4%) |
| **sdb** | WDC WD5000HHTZ-7 | 500GB | Empty GPT | Unused/Available |
| **sdc** | System Drive | 500GB | ext4 (Root) | 359GB (81%) |
| **nvme0n1** | NVMe SSD | 128GB | Encrypted | Unmounted |

## 🎯 **RECOMMENDED: Unified LVM Storage Pool**

### **Target Configuration**
Create a **2.5TB LVM storage pool** combining:
- **sda3** (2TB) - After backup and reformat
- **sdb** (500GB) - Ready to use immediately

### **Advantages of Multi-Drive LVM**
1. ✅ **Unified Storage**: Single 2.5TB logical space
2. ✅ **Flexibility**: Dynamic resizing of logical volumes
3. ✅ **Performance**: Can stripe across drives for speed
4. ✅ **Snapshots**: LVM snapshot capability for backups
5. ✅ **No Size Limits**: Eliminates FAT32 4GB file restriction
6. ✅ **Expandability**: Easy to add more drives later

## 📋 **Implementation Plan**

### **Phase 1: Prepare sdb (500GB) - IMMEDIATE**
```bash
# 1. Create LVM physical volume on sdb
sudo pvcreate /dev/sdb

# 2. Create initial volume group
sudo vgcreate storage_pool /dev/sdb

# 3. Create initial logical volumes
sudo lvcreate -L 200G -n projects storage_pool    # Development projects
sudo lvcreate -L 200G -n media storage_pool       # Media files
sudo lvcreate -L 50G -n backups storage_pool      # System backups
# Keep ~50GB free for expansion

# 4. Format with ext4
sudo mkfs.ext4 /dev/storage_pool/projects
sudo mkfs.ext4 /dev/storage_pool/media
sudo mkfs.ext4 /dev/storage_pool/backups

# 5. Create mount points and mount
sudo mkdir -p /mnt/storage/{projects,media,backups}
sudo mount /dev/storage_pool/projects /mnt/storage/projects
sudo mount /dev/storage_pool/media /mnt/storage/media
sudo mount /dev/storage_pool/backups /mnt/storage/backups
```

### **Phase 2: Backup & Prepare sda (2TB)**
```bash
# 1. Backup CBWHDD data to LVM
sudo rsync -av /media/cbwinslow/CBWHDD/ /mnt/storage/backups/cbwhdd_backup/

# 2. Unmount CBWHDD
sudo umount /media/cbwinslow/CBWHDD

# 3. Remove partition and prepare for LVM
sudo parted /dev/sda rm 3
sudo parted /dev/sda mkpart primary 3328000s 100%

# 4. Add to LVM pool
sudo pvcreate /dev/sda3
sudo vgextend storage_pool /dev/sda3
```

### **Phase 3: Expand and Organize**
```bash
# 1. Expand existing logical volumes
sudo lvextend -L +500G /dev/storage_pool/media      # Now 700GB total
sudo lvextend -L +300G /dev/storage_pool/projects   # Now 500GB total
sudo lvextend -L +200G /dev/storage_pool/backups    # Now 250GB total

# 2. Resize filesystems
sudo resize2fs /dev/storage_pool/media
sudo resize2fs /dev/storage_pool/projects
sudo resize2fs /dev/storage_pool/backups

# 3. Create additional logical volumes
sudo lvcreate -L 500G -n development storage_pool   # Development environments
sudo lvcreate -L 200G -n ai_models storage_pool     # AI/ML models
sudo lvcreate -L 100G -n docker storage_pool        # Docker volumes
# Keep ~500GB free for future use
```

## 🗂️ **Proposed Directory Structure**

```
/mnt/storage/
├── projects/          # 500GB - Active development projects
├── media/             # 700GB - Videos, images, large files
├── backups/           # 250GB - System and data backups
├── development/       # 500GB - Virtual environments, tools
├── ai_models/         # 200GB - LLM models, datasets
└── docker/            # 100GB - Docker volumes, containers
```

## ⚡ **Performance Optimization Options**

### **Option A: Striping for Speed** (Recommended)
```bash
# Create striped logical volumes for better performance
sudo lvcreate -L 500G -i 2 -I 64K -n fast_storage storage_pool
```

### **Option B: Linear for Reliability**
```bash
# Use linear allocation (default) for maximum reliability
# Data written to one drive completely before using next
```

### **Option C: Mirror for Redundancy** (Future)
```bash
# If adding more drives, create mirrors for critical data
sudo lvcreate -L 100G -m 1 -n critical_data storage_pool
```

## 📊 **Expected Benefits**

### **Performance Improvements**
- **Transfer Speed**: 2-3x faster than FAT32
- **File Operations**: Native Linux filesystem performance
- **No Size Limits**: Support for files >4GB

### **Storage Efficiency**
- **Unified Space**: 2.5TB appears as single pool
- **Dynamic Allocation**: Resize volumes as needed
- **No Waste**: Efficient space utilization

### **Management Benefits**
- **Snapshots**: Point-in-time backups with `lvcreate -s`
- **Online Resizing**: Grow/shrink without unmounting
- **Easy Expansion**: Add drives to pool anytime

## 🔄 **Migration Strategy**

### **Step 1: Immediate Setup (sdb only)**
- ⏱️ **Time**: 30 minutes
- ⚠️ **Risk**: Very low
- 💾 **Benefit**: 500GB LVM pool ready

### **Step 2: CBWHDD Integration**
- ⏱️ **Time**: 2-3 hours (backup + reformat)
- ⚠️ **Risk**: Medium (requires backup)
- 💾 **Benefit**: 2.5TB unified pool

### **Step 3: Optimization**
- ⏱️ **Time**: 1 hour
- ⚠️ **Risk**: Low
- 💾 **Benefit**: Organized structure + performance tuning

## 📋 **Auto-Mount Configuration**

### **/etc/fstab entries:**
```bash
# LVM Storage Pool
/dev/storage_pool/projects  /mnt/storage/projects     ext4  defaults,noatime  0  2
/dev/storage_pool/media     /mnt/storage/media        ext4  defaults,noatime  0  2
/dev/storage_pool/backups   /mnt/storage/backups      ext4  defaults,noatime  0  2
/dev/storage_pool/development /mnt/storage/development ext4  defaults,noatime  0  2
/dev/storage_pool/ai_models /mnt/storage/ai_models    ext4  defaults,noatime  0  2
/dev/storage_pool/docker    /mnt/storage/docker       ext4  defaults,noatime  0  2
```

## 🚨 **Backup Strategy During Migration**

### **Critical Data Protection**
1. **CBWHDD Backup**: Full rsync to new LVM before reformatting
2. **System Backup**: Create LVM snapshot before major changes
3. **Verification**: Check backup integrity before proceeding

### **Rollback Plan**
1. **Emergency Access**: CBWHDD data backed up to LVM
2. **Quick Restore**: Can reformat sda3 back to FAT32 if needed
3. **No Data Loss**: All operations preserve original data

## 🎯 **Immediate Action Plan**

### **Ready to Execute**
1. ✅ **Start with sdb**: Zero risk, immediate 500GB benefit
2. ✅ **Test LVM setup**: Validate configuration before CBWHDD
3. ✅ **Plan CBWHDD backup**: Ensure safe migration path

### **Next Steps**
Would you like me to:
1. **Start Phase 1** with sdb setup immediately?
2. **Create the backup plan** for CBWHDD first?
3. **Setup both drives** in a complete migration?

## 💡 **Additional Considerations**

### **Future Expansion**
- **RAID Integration**: LVM can work with hardware/software RAID
- **SSD Caching**: Use nvme0n1 as cache tier with `lvmcache`
- **Network Storage**: LVM can be shared via NFS/iSCSI

### **Monitoring Integration**
- **LVM Monitoring**: Integrate with existing system maintenance
- **Space Alerts**: Monitor volume group capacity
- **Performance Tracking**: Track I/O across logical volumes

Ready to proceed with the multi-drive LVM setup?

