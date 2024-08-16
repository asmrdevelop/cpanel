package Whostmgr::Transfers::Systems::Htaccess;

# cpanel - Whostmgr/Transfers/Systems/Htaccess.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
# RR Audit: JNK

use Cpanel::SafeFind                     ();
use Cpanel::AccessIds::ReducedPrivileges ();

use base qw(
  Whostmgr::Transfers::Systems
  Whostmgr::Transfers::SystemsBase::Frontpage
  Whostmgr::Transfers::SystemsBase::EA4
);

sub get_prereq {
    return [ 'Homedir', 'Unsuspend', 'userdata' ];
}

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This repairs [asis,EasyApache4] and removes legacy [asis,Frontpage] entries from [asis,.htaccess].') ];
}

sub get_restricted_available {
    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my ( $uid, $user_homedir ) = ( $self->{'_utils'}->pwnam() )[ 2, 7 ];

    # currently only restores with Frontpage or EasyApache4 need
    # htaccess updates
    my %user_functions;
    my %root_functions;
    $user_functions{'Frontpage'} = $self->can('purge_frontpage_from_htaccess')
      if ( $self->was_using_frontpage() );
    $root_functions{'EasyApache4'} = $self->can('repair_ea4_in_htaccess')
      if ( $self->was_using_ea4() );

    return ( 1, $self->_locale()->maketext('No need to update [asis,htaccess] files.') ) unless ( %root_functions || %user_functions );

    my $user = $self->newuser();
    my @htaccess_files;
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        $user,
        sub {
            # 1/ look for htaccess files
            $self->out( $self->_locale()->maketext( "Looking for “[_1]” files …", '.htaccess' ) );
            Cpanel::SafeFind::find(
                {
                    'wanted' => sub {
                        return unless $File::Find::name =~ m{/\.htaccess$};

                        # skip symlinks
                        return if -l $File::Find::name;

                        # need to check that the file belongs to the current user
                        my $file_uid = ( stat(_) )[4];
                        return unless $uid == $file_uid;

                        # need to be sure the file belongs to the user
                        push @htaccess_files, $File::Find::name;
                        return;
                    },
                    'no_chdir' => 1,
                },
                $user_homedir
            );

            $self->out( $self->_locale()->maketext( "Updating “[_1]”’s “[_2]” files …", $user, '.htaccess' ) );

            # 2/ update the htaccess files
            for my $func ( values %user_functions ) {
                foreach my $htaccess (@htaccess_files) {

                    # Method funcrefs can't really use the regular
                    # method-call syntax, so we have to fake it a bit.
                    $func->( $self, $htaccess );
                }
            }
        }
    );

    $self->out( $self->_locale()->maketext( "Updating the system’s web virtual host configuration cache and “[_1]” files …", '.htaccess' ) );

    if (@htaccess_files) {

        # The cache must be up to date to map document roots to vhosts
        require Cpanel::Config::userdata::UpdateCache;
        Cpanel::Config::userdata::UpdateCache::update($user);
    }

    # 2/ update the htaccess config
    for my $func ( values %root_functions ) {
        foreach my $htaccess (@htaccess_files) {

            # Method funcrefs can't really use the regular
            # method-call syntax, so we have to fake it a bit.
            $func->( $self, $htaccess );
        }
    }

    my @keys = sort ( keys %user_functions, keys %root_functions );
    return ( 1, $self->_locale()->maketext( "[list_and,_1] [numerate,_2,was,were] repaired in [asis,.htaccess] files.", \@keys, scalar(@keys) ) );
}

*restricted_restore = \&unrestricted_restore;

1;
