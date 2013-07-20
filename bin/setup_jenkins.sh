sudo stop jenkins
sudo rm -rf /scratch/aosp
sudo mkdir /scratch/aosp
sudo chown jenkins /scratch/aosp
sudo chgrp jenkins /scratch/aosp
sudo start jenkins
