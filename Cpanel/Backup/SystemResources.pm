package Cpanel::Backup::SystemResources;

# cpanel - Cpanel/Backup/SystemResources.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::Mailman::Filesys        ();
use Cpanel::SafeDir::MK             ();
use Cpanel::OS                      ();
use Cpanel::Config::IPs::RemoteDNS  ();
use Cpanel::Config::IPs::RemoteMail ();

# incomplete list, need to unshift the file_conf at run time via _init_FILES
my @FILES = qw(
  /etc/dovecot/sni.conf
  /etc/exim.conf
  /etc/exim.conf.local
  /etc/exim.conf.localopts
  /etc/exim.conf.localopts.shadow
  /etc/fstab
  /etc/group
  /etc/ips
  /etc/localdomains
  /etc/mailips
  /etc/manualmx
  /etc/master.passwd
  /etc/my.cnf
  /etc/named.conf
  /etc/namedb/named.conf
  /etc/passwd
  /etc/proftpd.conf
  /etc/pure-ftpd.conf
  /etc/rc.conf
  /etc/remotedomains
  /etc/reservedipreasons
  /etc/reservedips
  /etc/rndc.conf
  /etc/secondarymx
  /etc/senderverifybypasshosts
  /etc/spammeripblocks
  /etc/cpanel_exim_system_filter
  /etc/global_spamassassin_enable
  /etc/spammers
  /etc/shadow
  /etc/wwwacct.conf
  /root/.my.cnf
  /var/cpanel/greylist/conf
  /var/cpanel/greylist/greylist.sqlite
  /var/cpanel/mysql/remote_profiles/profiles.json
);

push @FILES, (
    Cpanel::Config::IPs::RemoteMail->PATH(),
    Cpanel::Config::IPs::RemoteDNS->PATH(),
);

{
    my $_initted;

    sub _init_FILES {
        return if $_initted;
        unshift @FILES, apache_paths_facade->file_conf();
        return;
    }
}

my @DIRS = (
    $Cpanel::ConfigFiles::VALIASES_DIR,
    $Cpanel::ConfigFiles::VDOMAINALIASES_DIR,
    $Cpanel::ConfigFiles::VFILTERS_DIR,
    $Cpanel::ConfigFiles::FTP_PASSWD_DIR,
    Cpanel::Mailman::Filesys::MAILMAN_DIR(),
    Cpanel::OS::user_crontab_dir(),
    qw(
      /etc/cpanel
      /etc/mail
      /etc/namedb
      /var/lib/rpm
      /var/lib/named/chroot/var/named/master
      /var/named
      /var/cpanel
      /var/spool/cron
      /var/cron/tabs
      /var/spool/fcron
      /var/log/bandwidth
      /usr/share/ssl
      /etc/pki/tls/certs
      /etc/ssl
      /var/ssl
    )
);

# This is where it will look for files containing lists of extra files
our $extra_files_folder = '/var/cpanel/backups/extras/';

sub get_resource_paths {
    my ($files_folder) = @_;
    if ($files_folder) {
        $extra_files_folder = $files_folder;
    }    # otherwise we use the default
    undef $files_folder;

    # Add any extra files to the @DIRS and @FILES array

    # Get all the files inside that directory
    my @file_list_files = ();
    {
        unless ( -e $extra_files_folder ) {
            unless ( Cpanel::SafeDir::MK::safemkdir($extra_files_folder) ) {
                print STDERR "[backup] Could not create $extra_files_folder : $!\n";
            }
        }

        my $dh;
        unless ( opendir $dh, $extra_files_folder ) {
            print STDERR "[backup] Unable to open $extra_files_folder:  $!";
            exit 1;
        }

        while ( my $file_name = readdir $dh ) {
            push @file_list_files, $extra_files_folder . $file_name;
        }

        closedir($dh);
    };

    _init_FILES();

    # go through each file and read its contents
    # read each as a list of files to backup
    foreach my $file (@file_list_files) {
        next unless ( -f $file );

        my $my_file_handle;
        unless ( open $my_file_handle, '<', $file ) {
            print STDERR "[backup] Unable to open $file:  $!";
        }

        # Each line in the file is an extra file to backup
        while ( my $line = <$my_file_handle> ) {
            chomp $line;

            unless ( -e $line ) {
                print STDERR "[backup] $line does not exist\n";
                next;
            }

            # Sort out whether it is a directory or not
            if ( -d $line ) {
                push @DIRS, $line;
            }
            else {
                push @FILES, $line;
            }
        }

        close $my_file_handle;
    }

    my $addtional_resources = {
        'files' => \@FILES,
        'dirs'  => \@DIRS,
    };
    return $addtional_resources;
}

sub get_excludes_args_by_path {
    my ($path) = @_;

    if ( $path eq '/var/cpanel' ) {
        return (
            '--exclude=lastrun/*',
            '--exclude=bwusagecache/*',
            '--exclude=serviceauth/*',
            '--exclude=dnsrequests_db/*',
            '--exclude=configs.cache/*',
            '--exclude=caches/*',
            '--exclude=pw.cache/*',
            '--exclude=@pwcache/*',
            '--exclude=template_compiles/*',
            '--exclude=locale/*',
            '--exclude=user_pw_cache/*',
            '--exclude=perl/*',
            '--exclude=php/sessions/*',
        );

    }
    return ("--exclude=*/proc/*");
}

sub get_defaults {
    _init_FILES();
    return ( \@FILES, \@DIRS );
}
1;
