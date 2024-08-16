package Cpanel::Security::Policy::SourceIPCheck;

# cpanel - Cpanel/Security/Policy/SourceIPCheck.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#use strict;

# The following dependencies must be included by cpsrvd.pl to be available in binary
use Cpanel::SecurityPolicy::Utils                 ();
use Cpanel::Security::Policy::SourceIPCheck::Util ();
use Cpanel::DNSLib::PeerConfig                    ();    # required by SourceIPCheck.
use Cpanel::LastLogin::Tiny                       ();    # required by SourceIPCheck.
use Cpanel::AccessIds::ReducedPrivileges          ();
use Cpanel::SV                                    ();

use Cpanel::Locale::Lazy 'lh';

my $locale;

use base 'Cpanel::SecurityPolicy::Base';

sub new {
    my ($class) = @_;

    # Compiler does not necessarily properly load the base class.
    unless ( exists $INC{'Cpanel/SecurityPolicy/Base.pm'} ) {
        eval 'require Cpanel::SecurityPolicy::Base;';
    }
    return Cpanel::SecurityPolicy::Base->init( __PACKAGE__, 20 );
}

sub fails {
    my ( $self, $sec_ctxt ) = @_;

    # Not supporting SourceIPCheck on webmail accounts.
    return 0 if $sec_ctxt->{'appname'} eq 'webmaild';

    my $homedir;
    my $user;
    my $cluster_request = $sec_ctxt->{'request_type'} eq 'dnsadmin' ? 1 : 0;
    if ( $sec_ctxt->{'is_possessed'} ) {
        $user    = $sec_ctxt->{'possessor'};
        $homedir = $sec_ctxt->{'possessor_homedir'};
    }
    else {
        $user    = $sec_ctxt->{'user'};
        $homedir = $sec_ctxt->{'homedir'};

        if ( $sec_ctxt->{'virtualuser'} ) {
            $sec_ctxt->{'domain'} =~ s/\///g;
        }
    }

    $homedir or die "Failed to get the user’s home directory from the sec_ctxt";

    Cpanel::SV::untaint($homedir);    # TODO: brute-force

    my $sec_policy_dir = Cpanel::SecurityPolicy::Utils::secpol_dir_from_homedir($homedir);

    Cpanel::SV::untaint($_) foreach ( $user, $sec_policy_dir );    # TODO: brute-force

    if ( !Cpanel::Security::Policy::SourceIPCheck::Util::has_security_questions( $sec_policy_dir, $user ) ) {

        # if not a normal request and no questions, let them in because they can't set
        # the questions and they would have been allowed in anyway.
        return $sec_ctxt->{'request_type'} eq 'normal' ? 1 : 0;
    }
    elsif ( !_ip_passes( $user, $sec_policy_dir, $sec_ctxt->{'remoteip'}, $cluster_request ) ) {
        return 1;
    }

    return 0;
}

sub fetch_ip_list {
    return Cpanel::Security::Policy::SourceIPCheck::Util::fetch_ip_list(@_);
}

#
# Look in $sec_policy_dir to see if $user has allowed this $remote_ip address
# as valid. If this is a $cluster_req, check the DNS cluster addresses instead.
#
# Return true if this address is valid, false otherwise.
sub _ip_passes {
    my $user           = shift;
    my $sec_policy_dir = shift;
    my $remote_ip      = shift;
    my $cluster_req    = shift;

    if ( !$remote_ip ) {
        Carp::confess("I am missing the users remote ip.  Security Policy requires exec termination.");
    }

    my $ipref = Cpanel::Security::Policy::SourceIPCheck::Util::fetch_ip_list( $sec_policy_dir, $user );
    if ( !$ipref ) {
        {
            my $priv_guard = ( $> || $user eq 'root' ) ? undef : Cpanel::AccessIds::ReducedPrivileges->new($user);

            # if no iplist, grandfather in the last login address. If no last, call again to update.
            my $last_ip = Cpanel::LastLogin::Tiny::lastlogin() || Cpanel::LastLogin::Tiny::lastlogin();
            if ( $last_ip =~ m/^[\d.]+$/ ) {
                Cpanel::Security::Policy::SourceIPCheck::Util::authorize_ip( $sec_policy_dir, $user, $last_ip );
            }
        }
        $ipref = Cpanel::Security::Policy::SourceIPCheck::Util::fetch_ip_list( $sec_policy_dir, $user );
        return 0 unless $ipref;
    }

    if ($ipref) {
        if ( _ip_in_cache( $remote_ip, $ipref ) ) {
            return 1;
        }
    }
    local $ENV{'REMOTE_USER'} = $user;
    if ($cluster_req) {
        foreach my $ip ( Cpanel::DNSLib::PeerConfig::getdnspeers() ) {
            return 1 if _ip_match( $remote_ip, $ip );
        }
    }

    return 0;
}

#
# Given an IP address, generate the class a, class b, and class c subnets.
sub _list_subnets {
    my $ip = shift;

    $ip =~ m/^(((\d+\.)\d+\.)\d+\.)/;

    return ( $3 . '*.*.*', $2 . '*.*', $1 . '*' );
}

#
# Return true if $remote_ip exists in the supplied ip list file.
sub _ip_in_list_file {
    my ( $remote_ip, $ip_list_file ) = @_;

    if ( open( my $ip_fh, '<', $ip_list_file ) ) {
        while ( readline($ip_fh) ) {
            chomp();
            if ( _ip_match( $remote_ip, $_ ) ) {
                return 1;
            }
        }
        close($ip_fh);
    }

    return 0;
}

#
# Return true if $remote_ip exists in the $ipcache hash. $ipcache can contain
# the full ip address, or a class a, class b, or class c subnet.
sub _ip_in_cache {
    my $remote_ip = shift;
    my $ipcache   = shift;

    if ( !$remote_ip ) {
        Carp::confess("I am missing the users remote ip.  Security Policy requires exec termination.");
    }

    if ( $ipcache->{$remote_ip} ) {
        return 1;
    }

    my ( $class_a_match, $class_b_match, $class_c_match ) = _list_subnets($remote_ip);

    return ( $ipcache->{$class_a_match} || $ipcache->{$class_b_match} || $ipcache->{$class_c_match} );
}

#
# Return true if $remote_ip matches $iptarget. $iptarget can be a full ip address,
# or a class a, class b, or class c subnet.
sub _ip_match {
    my $remote_ip = shift;
    my $iptarget  = shift;

    if ( !$remote_ip ) {
        Carp::confess("I am missing the users remote ip.  Security Policy requires exec termination.");
    }

    if ( $remote_ip eq $iptarget ) {
        return 1;
    }

    my ( $class_a_match, $class_b_match, $class_c_match ) = _list_subnets($remote_ip);

    return ( $iptarget eq $class_a_match || $iptarget eq $class_b_match || $iptarget eq $class_c_match );
}

sub description {
    return lh()->maketext('Limit logins to verified IP addresses.');
}

1;
