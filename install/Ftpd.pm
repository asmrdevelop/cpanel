package Install::Ftpd;

# cpanel - install/Ftpd.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;

use Cpanel::Services::Enabled ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Call bin/build_ftp_conf which relocates /var/log/xferlog
    to the apache /ftpxferlog directory and performs several
    ftpd configuration sanity checks.

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('ftpd');

    return $self;
}

sub perform {
    my $self = shift;

    # FTP is now disabled by default on new installs.
    return 1 if $ENV{'CPANEL_BASE_INSTALL'} || !Cpanel::Services::Enabled::is_enabled('ftp');

    require '/usr/local/cpanel/bin/build_ftp_conf';    ##no critic qw(RequireBarewordIncludes)
    local $@;
    eval { bin::build_ftp_conf->script(); };
    warn if $@;

    return 1;
}

1;

__END__
