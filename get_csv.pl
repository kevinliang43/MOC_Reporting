use YAML::XS;
use Parse::CSV;
use JSON;
use Data::Dumper;
use Time::Local;
use Date::Parse;
use WWW::Curl::Easy;
use WWW::Curl::Multi;
use DBI;
use POSIX;
use strict;

# $projects->uuid = [project uuid]
#                ->name = [project name]
#                ->id   = [project id in cloud forms (will go away)]
#                ->VM   = [hash of VMs in this project (added later)] MVP
#                ->Vol  = [hash of the Volumes in this project (added later)] MVP
#                ->Obj  = [hash of the object stores in this project (added later)]
#          ->os_id->Con  = [has of the containers in this project (added later) ]

sub read_projects
    {
    my $fname=shift;
    my $proj;

    my $data_set=open_csv($fname);

    # id,name,ems_ref,ems_id,description
    while(my $line=$data_set->fetch())
        {
        my $id=$line->{'id'};
        $proj->{$id}->{'name'} = $line->{'name'};
        $proj->{$id}->{'uuid'} = $line->{'ems_ref'};
        $proj->{$id}->{'vm_cnt'} = 0;
        $proj->{$id}->{'vol_cnt'} = 0;
        $proj->{$id}->{'event_cnt'} = 0;
        #$proj->{$id}->{} = $line{'ems_id'};
        }
    #print Dumper($proj);
    return $proj;
    }

sub read_flavors
    {
    my $fname=shift;
    my $flavor;

    my $data_set=open_csv($fname);
    # id,name,cpus,memory,root_disk_size,ems_ref
    while(my $line=$data_set->fetch())
        {
        my $id=$line->{'id'};
        $flavor->{$id}->{'name'}=$line->{'name'};
        $flavor->{$id}->{'cpus'}=$line->{'cpus'};
        $flavor->{$id}->{'mem'}=$line->{'memory'}/1073741824;
        $flavor->{$id}->{'disk'}=1.0*$line->{'root_disk_size'}/1073741824;
        $flavor->{$id}->{'cost'}= 0.1*$line->{'cpus'} + 0.2*$flavor->{'mem'};
        }
    return $flavor;
    }

# This takes a projct datastructure and adds in the VM information
sub read_vms
    {
    my $proj=shift;
    my $fname=shift;
    
    my $data_set=open_csv($fname);
    #id,name,guid,flavor_id,tenant_id
    while(my $line=$data_set->fetch())
        {
        my $proj_id = $line->{'tenant_id'};
        #my $uuid = $line->{'guid'};
        my $uuid = $line->{'id'};
        $proj->{$proj_id}->{'vm_cnt'}=1; # just set this to 1 for now.
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'event_cnt'}=0;
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'name'}=$line->{'name'};
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'flavor_id'}=$line->{'flavor_id'};
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'id'}=$line->{'id'};
        $proj->{$proj_id}->{'VM'}->{$uuid}->{'id'}=$line->{'guid'};
        }

    # count up the VMs
    # not yet though.
    return $proj;
    }
 
sub read_vol
    {
    my $proj=shift;
    my $fname=shift;
    
    my $data_set=open_csv($fname);
    #id,name,ems_ref,cloud_tenant_id,volume_type
    while(my $line=$data_set->fetch())
        {
        my $proj_id = $line->{'cloud_tenant_id'};
        my $uuid = $line->{'id'};
        $proj->{$proj_id}->{vol_cnt}=1;
        $proj->{$proj_id}->{'VOL'}->{$uuid}->{'name'}=$line->{'name'};     
        $proj->{$proj_id}->{'VOL'}->{$uuid}->{'type'}=$line->{'volume_type'};     
        $proj->{$proj_id}->{'VOL'}->{$uuid}->{'type'}=$line->{'ems_ref'};    # this is the openstack uuid     
        #$proj->{$proj_id}->{'VOL'}->{$uuid}->{'size'}=$line->{'size'};     
        
        }
    return $proj;
    }

1;

