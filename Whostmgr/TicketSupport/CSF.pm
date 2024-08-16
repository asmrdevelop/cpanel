
# cpanel - Whostmgr/TicketSupport/CSF.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::TicketSupport::CSF;

use strict;

use base 'Whostmgr::TicketSupport::Whitelist';

use Cpanel::FindBin  ();
use Cpanel::Binaries ();

my ( $gl_csf_bin, $gl_grep_bin );

sub STATUS_NAME { return 'csf_wl_status'; }

=head1 NAME

Whostmgr::TicketSupport::CSF

=head1 DESCRIPTION

cPanel support IP whitelist for CSF -- only used if the /etc/csf directory is present on the system.

=head1 METHODS

=head2 $wl_obj->setup()

Add the whitelist entries to /etc/csf/csf.allow

=cut

sub setup {
    my ($self) = @_;
    $gl_csf_bin ||= Cpanel::FindBin::findbin('csf');
    my @ips = map { $_->{'ip'} } @{ $self->{'access_ips'} };
    my $ok  = 1;
    $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Setting up cPanel support access CSF whitelist rules");
    for my $ip (@ips) {
        system $gl_csf_bin, '-a', $ip, 'cPanel-support-access';
        $ok = 0 if $?;
    }
    return $ok;
}

=head2 $wl_obj->unsetup()

Remove any whitelist entries from /etc/csf/csf.allow that have
"cPanel-support-access" in the comment field.

=cut

sub unsetup {
    my ($self) = @_;
    $gl_csf_bin ||= Cpanel::FindBin::findbin('csf');
    my @ips = _find_matches();
    my $ok  = 1;
    $Whostmgr::TicketSupport::Whitelist::gl_logger->info("Removing cPanel support access CSF whitelist rules");
    for my $ip (@ips) {
        system $gl_csf_bin, '-ar', $ip;
        $ok = 0 if $?;
    }
    return $ok;
}

=head2 $wl_obj->active()

Returns a boolean value indicating whether the cPanel support IPs are
whitelisted in CSF.

=cut

sub active {
    my ($self) = @_;
    my @expect = map { $_->{'ip'} } @{ $self->{'access_ips'} };
    my %have   = map { $_ => 1 } _find_matches();
    for my $ip (@expect) {
        return 1 if $have{$ip};    # If we have at least one of our rules left, call it active
    }
    return;
}

=head2 $wl_obj->should_skip()

Returns a boolean value indicating whether CSF should be skipped on the system in question.

Skip CSF if CSF either isn't installed or is disabled.

=cut

sub should_skip {
    return !-e '/etc/csf' || -e '/etc/csf/csf.disable';
}

sub _find_matches {
    $gl_grep_bin ||= Cpanel::Binaries::path('grep');
    return grep { $_ } map { (m{^([^\#\s]+)})[0] } `$gl_grep_bin cPanel-support-access /etc/csf/csf.allow 2>/dev/null`;
}

1;
