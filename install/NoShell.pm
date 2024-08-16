package Install::NoShell;

# cpanel - install/NoShell.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw( Cpanel::Task );

use strict;
use warnings;
use Cpanel::FileUtils::Lines ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Add shells to /etc/shells

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

    $self->set_internal_name('noshell');

    return $self;
}

sub _add_shell_if_necessary {
    my $name       = shift;
    my $path       = shift;
    my $shell_file = '/etc/shells';

    if (   !Cpanel::FileUtils::Lines::has_txt_in_file( $shell_file, $name )
        && !Cpanel::FileUtils::Lines::appendline( $shell_file, $path ) ) {
        warn 'Failed to add to /etc/shells';
        return;
    }

    return 1;
}

sub perform {
    my $self           = shift;
    my %path_for_shell = (
        'jailshell' => '/usr/local/cpanel/bin/jailshell',
        'noshell'   => '/usr/local/cpanel/bin/noshell',
        'ftpsh'     => '/bin/ftpsh',
        'false'     => '/bin/false',
    );

    # Sort for testing
    foreach my $key ( sort keys %path_for_shell ) {
        _add_shell_if_necessary( $key, $path_for_shell{$key} );
    }

    return 1;
}

1;

__END__
