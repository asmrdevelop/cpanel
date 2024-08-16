package Install::RemoveLegacyTouchFiles;

# cpanel - install/RemoveLegacyTouchFiles.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw( Cpanel::Task );

use Cpanel::FileUtils::Link ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Cleanup legacy 'flag' files which were previously used by cPanel&WHM

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('removelegacytouchfiles');

    return $self;
}

sub _files {
    return [
        qw{
          /var/cpanel/easy_skip_cpanelsync
          /var/cpanel/use_legacy_cpan
          /var/cpanel/hooks.yaml
          /var/cpanel/available_rpm_addons.cache
        }
    ];
}

sub perform {
    my ($self) = @_;

    foreach my $f ( $self->_files->@* ) {
        Cpanel::FileUtils::Link::safeunlink($f);
    }

    return 1;
}

1;

__END__
