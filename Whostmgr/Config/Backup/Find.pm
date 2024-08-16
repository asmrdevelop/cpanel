package Whostmgr::Config::Backup::Find;

# cpanel - Whostmgr/Config/Backup/Find.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION = 1.1;

use Whostmgr::Config::Backup ();

sub list_backups_on_server {
    my %OPTS       = @_;
    my $module_ref = $OPTS{'modules'};

    my $backup = Whostmgr::Config::Backup->new();

    $backup->_load_modules();    #not for public api

    my %VERSIONS;
    foreach my $module ( keys %{$module_ref} ) {
        if ( !exists $backup->{'modules'}->{$module} || !ref $backup->{'modules'}->{$module} ) {
            return ( 0, "The module $module could not be loaded" );
        }
        $VERSIONS{$module} = $backup->{'modules'}->{$module}->version();
    }

    my $type_regex = ref $module_ref ? join( "_", map { $_ =~ s/::/__/g; quotemeta($_) . '-[^-]+' } sort keys %{$module_ref} ) : 'all-[^-]+';

    my @backups;
    if ( opendir( my $dir_fh, '/var/cpanel/config.backups' ) ) {
        foreach my $bck (

            # note: using a simple sort { $b cmp $a } here, should be good enough...
            sort {
                ( ( $b =~ /([0-9]+)\./ )[0] || 0 )

                  <=>

                  ( ( $a =~ /([0-9]+)\./ )[0] || 0 )

            } readdir($dir_fh)
        ) {
            next if ( $bck eq '.' || $bck eq '..' );
            if ( $bck =~ m/^whm-config-backup-($type_regex)-([0-9]+)/ ) {
                my $backup_time    = $2;
                my $backup_version = ( split( /-/, $1 ) )[-1];
                push @backups, { 'file' => $bck, 'servertime' => scalar localtime($backup_time), 'time' => $backup_time, 'version' => $backup_version };
            }
        }
        closedir($dir_fh);
    }
    return ( 1, "Backups Found", \@backups );
}
1;
