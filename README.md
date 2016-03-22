# brbox-plus
experimental brbox for improved structure with easy buildroot integration

# Instructions

After cloning the repository just run "sudo ./create_image.sh -c config_name".
To support out-of-tree builds an additional parameter -o can be passed:
"sudo ./create_image.sh -c config_name -o /tmp/builddir".

Run "./create_image.sh -l" to view the available config.

To modify package in the buildroot-tree copy the folder to the 
br_external-folder and add an .override file ind this folder.
