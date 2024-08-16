package Cpanel::Config::LoadUserDomains::Count;

# cpanel - Cpanel/Config/LoadUserDomains/Count.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie            qw(exists);
use Cpanel::LoadFile::ReadFast ();
use Cpanel::ConfigFiles        ();

=head1 NAME

Cpanel::Config::LoadUserDomains::Count

=cut

=head2 counttrueuserdomains()

Count the number of main domains (cpanel users)
on the system

=cut

sub counttrueuserdomains {
    if ( !Cpanel::Autodie::exists( _trueuserdomains() ) ) {
        return 0;
    }
    return _count_file_lines( _trueuserdomains() );
}

=head2 countuserdomains()

Count the number of domains on all cpanel accounts
on the system

=cut

sub countuserdomains {
    if ( !Cpanel::Autodie::exists( _userdomains() ) ) {
        return 0;
    }
    return _count_file_lines( _userdomains() ) - 1;    # -1 for *: nobody
}

sub _count_file_lines {
    my ($file) = @_;
    open( my $ud_fh, '<', $file ) or die "open($file): $!";

    my $buffer = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $ud_fh, $buffer );
    my $num_ud = ( $buffer =~ tr/\n// );
    close($ud_fh) or warn "close($file): $!";

    # In case the file lacks a trailing newline.
    $num_ud++ if length($buffer) && substr( $buffer, -1 ) ne "\n";

    return $num_ud;
}

# allow an easy way to mock for testing
sub _userdomains {
    return $Cpanel::ConfigFiles::USERDOMAINS_FILE;
}

sub _domainusers {
    return $Cpanel::ConfigFiles::DOMAINUSERS_FILE;
}

sub _trueuserdomains {
    return $Cpanel::ConfigFiles::TRUEUSERDOMAINS_FILE;
}

1;
