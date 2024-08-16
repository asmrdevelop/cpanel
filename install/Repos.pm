package Install::Repos;

# cpanel - install/Repos.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base qw( Cpanel::Task );

use Cpanel::OS           ();
use Cpanel::Repos        ();
use Cpanel::SysPkgs      ();
use Cpanel::SysPkgs::YUM ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Assure optional repos are installed and enabled on some distros.

=over 1

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new ($proto) {
    my $self = $proto->SUPER::new;

    $self->set_internal_name('enable_repos');

    return $self;
}

sub perform ($self) {

    assure_epel();
    enable_repositories();
}

sub assure_epel {

    # Ensure epel-release repo package is installed on servers that need to use it
    return 1 unless Cpanel::OS::list_contains_value( 'package_repositories', 'epel' );

    return 2 if Cpanel::SysPkgs::YUM::is_epel_installed();

    # FIXME: CloudLinux 8 can't bootstrap EPEL from stock repositories.
    my $syspkgs = Cpanel::SysPkgs->new;
    $syspkgs->install( 'packages' => ['epel-release'] );
    $syspkgs->repolist();

    return 3;
}

sub enable_repositories {
    my @additional_repos = Cpanel::OS::package_repositories()->@* or return 1;

    my $repos_obj = Cpanel::Repos->new();
    foreach my $repo (@additional_repos) {
        $repos_obj->enable_repo_target( target_name => $repo );
    }

    return 2;
}

1;
