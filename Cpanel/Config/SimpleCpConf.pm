package Cpanel::Config::SimpleCpConf;

# cpanel - Cpanel/Config/SimpleCpConf.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::Config::SimpleCpConf

=head1 DESCRIPTION

Simple wrapper to retrieve and update cpanel.config.  The difference
with this module is that it uses Cpanel::Exception to perform
minimal validation with an error has occurred.

NOTE: In the long run, it would be best to utilize the Cpanel::Transaction
system instead of duct-taping around ::Guard problems.

=cut

use strict;
use warnings;
use Cpanel::Exception           ();
use Cpanel::Config::CpConfGuard ();
use Cpanel::Config::LoadCpConf  ();

=pod

=head2 B<get_cpanel_config($key)>

Retrieve the value of a key within cpanel.config

    INPUT
        N/A

    OUTPUT
        hash ref -- key/value pairs within cpanel.config

=cut

*get_cpanel_config = \&Cpanel::Config::LoadCpConf::loadcpconf;

=pod

=head2 B<set_cpanel_config( { $key =E<gt> $value } )>

Update cpanel.config with new values.  Throws a Cpanel::Exception if it fails
to save.   If the value of a key is undef, then the key will be deleted from
cpanel.config.

    INPUT
        hash ref -- key/value pairs to set

    OUTPUT
        truthy value -- success
        throw Cpanel::Exception -- failure

=cut

sub set_cpanel_config {
    my $href = shift;    # hash ref of key/value pairs

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'hashref' ] ) unless defined $href and ref($href) eq 'HASH';
    my $conf = Cpanel::Config::CpConfGuard->new();

    while ( my ( $key, $value ) = each(%$href) ) {
        if ( defined $value ) {
            $conf->{data}->{$key} = $value;
        }
        else {
            $conf->{data}->{$key} = '';
        }
    }

    die Cpanel::Exception::create( 'IO::FileWriteError', q{You do not have permission to update “[_1]”.}, ['cpanel.config'] ) unless $conf->save();

    return 1;
}

=pod

=head1 CONFIGURATION AND ENVIRONMENT

The module requires no configuration files or environment variables.

=head1 INCOMPATIBILITIES

None reported.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2015, cPanel, Inc. All rights reserved. This code is
subject to the cPanel license. Unauthorized copying is prohibited

=cut

1;
