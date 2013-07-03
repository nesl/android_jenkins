___Expected configuration___

`cp -r bin /aosp/bin`

`cp -r jobs ${JENKINS_HOME}/jobs`

  - The Android job requires a local mirror in `/aosp/mirror`
   
    Refer: `http://source.android.com/source/downloading.html#using-a-local-mirror`

  - The Kernel job requires a local mirror of the kernel projects in `/aosp/kernel_mirror`
  
    Look at the `kernel_mirror_platform_manifest.git` to set that up.
