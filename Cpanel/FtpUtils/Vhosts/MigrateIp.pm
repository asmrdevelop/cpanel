package Cpanel::FtpUtils::Vhosts::MigrateIp;

# cpanel - Cpanel/FtpUtils/Vhosts/MigrateIp.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::FtpUtils::Config::Proftpd::CfgFile ();
use Cpanel::SafeFile                           ();
use Cpanel::IP::Parse                          ();

use strict;

our $METHOD_DUPLICATE_IN_MAP  = 'duplicate_in_map';
our $METHOD_REMOVE_IPS_IN_MAP = 'remove_ips_in_map';

sub migrate_ips {
    my %OPTS = @_;

    my $ipmap         = $OPTS{'ipmap'};
    my $ftpdconf_fh   = $OPTS{'ftpconf_fh'};
    my $ftpdconf_lock = $OPTS{'ftpconf_lock'};
    my $keep_locked   = $OPTS{'keep_locked'};
    my $method        = $OPTS{'method'} || 'duplicate_in_map';    # by default we take the ips in the
                                                                  # ipmap hash and add the values to places where the keys are used

    if ( $method ne 'duplicate_in_map' && $method ne 'remove_ips_in_map' ) {
        return { 'status' => 0, 'statusmsg' => "'$method' is not a supported method" };
    }
    elsif ( !ref $ipmap || !scalar keys %{$ipmap} ) {
        return { 'status' => 0, 'statusmsg' => "'ipmap' is required, and must be a non-empty hashref" };
    }

    my $ftpdconf = Cpanel::FtpUtils::Config::Proftpd::CfgFile::bare_find_conf_file();

    my $proftpd_conf_is_open = ( $ftpdconf_lock ? 1 : 0 );
    if ( !$proftpd_conf_is_open ) {
        $ftpdconf_lock = Cpanel::SafeFile::safeopen( $ftpdconf_fh, '+<', $ftpdconf )
          or return { 'status' => 0, 'statusmsg' => 'Could not open the ftpconf file' };
    }
    else {
        seek $ftpdconf_fh, 0, 0;
    }

    my @PROFTPDC = <$ftpdconf_fh>;
    seek( $ftpdconf_fh, 0, 0 );

    foreach (@PROFTPDC) {
        if (m/^\s*<VirtualHost/i) {
            my $vhostline = $_;
            $vhostline =~ s/^\s+//;
            $vhostline =~ s/[\>\s\n]+$//;

            my (@currentips_list) = split( /\s+/, $vhostline );
            shift(@currentips_list);    #remove VirtualHost
            my @newips_list;
            foreach my $ip (@currentips_list) {
                my $currentip = ( Cpanel::IP::Parse::parse( $ip, undef, $Cpanel::IP::Parse::BRACKET_IPV6 ) )[1];
                if ( my $newip = $ipmap->{$currentip} ) {
                    next if $method eq 'remove_ips_in_map';
                    push @newips_list, $newip;
                }
                push @newips_list, $currentip;
            }
            print {$ftpdconf_fh} "<VirtualHost " . join( ' ', @newips_list ) . ">\n";
        }
        else {
            print {$ftpdconf_fh} $_;
        }
    }
    truncate( $ftpdconf_fh, tell($ftpdconf_fh) );

    Cpanel::SafeFile::safeclose( $ftpdconf_fh, $ftpdconf_lock ) unless $keep_locked;

    # TODO: syntax check || revert && return;
    return { 'status' => 1, 'statusmsg' => 'Vhosts Migrated' };
}

1;
