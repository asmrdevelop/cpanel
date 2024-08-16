package Install::MigrateResellerACLs;

# cpanel - install/MigrateResellerACLs.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Task );

use Try::Tiny;
use Cpanel::SafeRun::Object ();

our $VERSION = '1.0';

=head1 DESCRIPTION

    Update the ACLs assigned to resellers to include the 'default' set of ACLs.
    use Install::MigrateResellerACLs;

    Install::MigrateResellerACLs->new->perform();

=over

=item Type: Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub new {
    my $proto = shift;
    my $self  = $proto->SUPER::new;

    $self->set_internal_name('migrate_reseller_acls_98');

    # The file has to be there before we fix it.
    $self->add_dependencies(qw( ResellersInit ));

    return $self;
}

sub perform {
    my $self = shift;

    my $ret = $self->do_once(
        version => '11100_migrate_reseller_acls',
        eol     => 'never',
        code    => sub {
            my $run = Cpanel::SafeRun::Object->new(
                'program' => '/usr/local/cpanel/scripts/fix_reseller_acls',
                'args'    => [
                    qw(
                      --add-default-privs
                      --all-resellers
                      --all-acl-lists
                    )
                ]
            );
            return 1 unless $run->CHILD_ERROR();

            require Cpanel::Logger;
            Cpanel::Logger->new->warn( $run->stderr() );
            return 0;
        },
    );

    return $ret;
}

1;
