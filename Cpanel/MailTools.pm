package Cpanel::MailTools;

# cpanel - Cpanel/MailTools.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpConf           ();
use Cpanel::PwCache                      ();
use Cpanel::PwCache::Get                 ();
use Cpanel::ConfigFiles                  ();
use Cpanel::Email::Constants             ();
use Cpanel::MailTools::DBS               ();
use Cpanel::LoadModule                   ();
use Cpanel::FileUtils::TouchFile         ();
use Cpanel::AccessIds::ReducedPrivileges ();

our $VMAIL_DIR = '/etc/vmail';

our $VERSION = '1.2';

sub getdefaultmailaction {
    my $user    = shift;
    my $rCPCONF = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return $user if !exists $rCPCONF->{'defaultmailaction'};

    if ( $rCPCONF->{'defaultmailaction'} eq 'blackhole' ) {
        return ':blackhole:';
    }
    elsif ( $rCPCONF->{'defaultmailaction'} eq 'fail' ) {
        return ':fail: No Such User Here';
    }
    else {
        return $user;
    }
}

my $mailgid;

#TODO: Pass exceptions.
sub setupusermaildomainforward {
    my %OPTS        = @_;
    my $user        = $OPTS{'user'};
    my $domain      = $OPTS{'olddomain'};
    my $ndomain     = $OPTS{'newdomain'};
    my $nooverwrite = $OPTS{'nooverwrite'};
    my $nomaildbs   = $OPTS{'nomaildbs'};

    my ( $uid, $homedir ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 7 ];

    if ( !$nooverwrite || !-e "$Cpanel::ConfigFiles::VALIASES_DIR/$ndomain" ) {
        if ( open( my $vaf_fh, ">", "$Cpanel::ConfigFiles::VALIASES_DIR/$ndomain" ) ) {
            print {$vaf_fh} "*: " . Cpanel::MailTools::getdefaultmailaction($user) . "\n";
            close($vaf_fh);
        }
    }

    my @files = map { "$_/$ndomain" } (
        $Cpanel::ConfigFiles::VALIASES_DIR,
        $Cpanel::ConfigFiles::VDOMAINALIASES_DIR,
        $Cpanel::ConfigFiles::VFILTERS_DIR,
    );

    for my $file (@files) {
        if ( !-e $file ) {
            Cpanel::FileUtils::TouchFile::touchfile($file);
        }
    }

    chmod( Cpanel::Email::Constants::VFILE_PERMS(), @files );

    $mailgid ||= Cpanel::PwCache::Get::getgid('mail');
    chown $uid, $mailgid, @files;    #safe

    #TODO: Pass this up the chain. As of Dec 2013 nothing expects errors from
    #this code, though.
    local $@;
    eval { _handle_etc_vfilter_contents( $ndomain, $user ) } or do {
        warn "Error editing vfilters file for $ndomain: $@";
    };

    #
    # No need to remove service (formerly proxy) subdomains here as all callers will already set them up
    # and local is always assumed here
    #
    unless ($nomaildbs) {
        Cpanel::MailTools::DBS::setup( $ndomain, 'localdomains' => 1, 'remotedomains' => 0, 'secondarymx' => 0, 'update_proxy_subdomains' => 0 );
    }

    return 1;
}

sub removedomain {
    my $domain = shift;
    unlink(
        "$Cpanel::ConfigFiles::VALIASES_DIR/$domain",
        "$Cpanel::ConfigFiles::VDOMAINALIASES_DIR/${domain}",
        "$Cpanel::ConfigFiles::VFILTERS_DIR/${domain}"
    );

    #
    # No need to remove service (formerly proxy) subdomains here as they will be removed with the zone already
    #
    return Cpanel::MailTools::DBS::setup( $domain, 'localdomains' => 0, 'remotedomains' => 0, 'secondarymx' => 0, 'update_proxy_subdomains' => 0 );
}

sub remove_vmail_files {
    my ($domain) = @_;

    unlink map { "$VMAIL_DIR/$_.$domain" } qw(vhost uid gid passwd shadow);

    return;
}

## note: there is a similar clause in ::DnsUtils that creates an empty vfilter,
##   but only in the case of addons and parked
sub _handle_etc_vfilter_contents {
    my ( $ndomain, $username ) = @_;

    my $vfilters_file = "$Cpanel::ConfigFiles::VFILTERS_DIR/$ndomain";

    Cpanel::LoadModule::load_perl_module('Cpanel::Email::Filter');

    ## blank $account arg, as these are account level filters
    my $storefile = Cpanel::Email::Filter::fetchfilterstore_by_user_from_whm($username);

    if ( $storefile && -e $storefile && !-z _ ) {
        open( my $vf, '>>', $vfilters_file ) or do {
            die "open( >>, $vfilters_file ) failed: $!";
        };

        my $fstore;
        {
            my $privs_obj = Cpanel::AccessIds::ReducedPrivileges->new($username);
            $fstore = Cpanel::Email::Filter::_fetchfilter($storefile);
        }
        my $stordir     = Cpanel::Email::Filter::compute_exim_filter_stordir_from_whm();
        my $exim_filter = Cpanel::Email::Filter::_generate_exim_filter_string( $fstore, $stordir );
        print {$vf} $exim_filter or die "Failed write to $vfilters_file: $!";

        close($vf) or warn "close($vfilters_file) failed: $!";
    }

    return 1;
}

1;
