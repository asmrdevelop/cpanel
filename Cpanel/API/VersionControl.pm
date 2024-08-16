package Cpanel::API::VersionControl;

# cpanel - Cpanel/API/VersionControl.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                        ();
use Cpanel::Fileman::Reserved     ();
use Cpanel::JSON                  ();
use Cpanel::LoadModule            ();
use Cpanel::Shell                 ();
use Cpanel::VersionControl        ();
use Cpanel::VersionControl::Cache ();
use HTML::Entities                ();

our %API = (
    _needs_feature => 'version_control',
);

=head1 SUBROUTINES

=over 4

=item create()

Creates a new repository.

=cut

sub create {
    my ( $args, $result ) = @_;

    my $repo_root = $args->get_length_required('repository_root');
    if ( Cpanel::VersionControl::Cache::repo_exists($repo_root) ) {
        $result->error( "The proposed repository root, [_1], is already under version control.", $repo_root );
        return;
    }
    if (   $repo_root =~ m~^$Cpanel::homedir/?$~
        || $repo_root !~ m/^$Cpanel::homedir/ ) {
        $result->error( '“[_1]” is not a valid “[_2]”.', HTML::Entities::encode_entities($repo_root), 'repository_root' );
        return;
    }
    if ( $repo_root =~ m,^$Cpanel::homedir/(.+)$,
        && Cpanel::Fileman::Reserved::is_reserved($1) ) {
        $result->error( '“[_1]” is a directory reserved for cPanel use”.', HTML::Entities::encode_entities($repo_root) );
        return;
    }

    my $args_hr = _convert_args($args);

    my $vc = Cpanel::VersionControl->new(%$args_hr);
    $result->data( _freeze_object($vc) );

    return 1;
}

=item retrieve()

Lists existing repositories.

=cut

sub retrieve {
    my ( $args, $result ) = @_;

    my $fields = _convert_fields_arg($args);

    # Apply the filters to the list *before* we do a serialize on each.
    # serialize can be expensive for some repos, because of data that we
    # can't reasonably cache.
    my $vcs = Cpanel::VersionControl::Cache::retrieve();
    for my $filter ( @{ $args->filters() } ) {
        $filter->apply($vcs);
    }
    $result->data( [ map { _freeze_object( $_, $fields ) } @$vcs ] );

    return 1;
}

=item update()

Change an existing repository.

=cut

sub update {
    my ( $args, $result ) = @_;

    my $repo_root = $args->get_length_required('repository_root');
    my $args_hr   = _convert_args($args);

    my $vc = Cpanel::VersionControl::Cache::retrieve($repo_root);
    if ( !$vc ) {
        $result->error( '“[_1]” is not a valid “[_2]”.', HTML::Entities::encode_entities($repo_root), 'repository_root' );
        return;
    }

    $vc->update(%$args_hr);

    $result->data( _freeze_object($vc) );

    return 1;
}

=item delete()

Delete a repository. This will simply remove the repository from the
cpanel-controlled list of repositories, but will not remove any files
from user directory.

=cut

sub delete {
    my ( $args, $result ) = @_;

    my $repo_root = $args->get_length_required('repository_root');

    my $tasks = _user_tasks($repo_root);
    if ( scalar @{$tasks} ) {
        $result->error( '“[_1]” can not be deleted because there are tasks pending.', $repo_root );
        return;
    }

    my $vc = Cpanel::VersionControl::Cache::retrieve($repo_root);
    $vc->remove();

    return 1;
}

=back

=cut

# Any arguments a user cares to pass into these functions are fine,
# but the objects will ignore everything that they don't specifically
# recognize for the function they are performing.  Some of our
# arguments are in encoded JSON, so we need to decode them before we
# pass them into the objects.
sub _convert_args {
    my ($args) = @_;

    my $args_hr = $args->get_raw_args_hr();

    if ( defined $args_hr->{'source_repository'} ) {
        $args_hr->{'source_repository'} = Cpanel::JSON::LoadNoSetUTF8( $args_hr->{'source_repository'} );
    }

    return $args_hr;
}

# We respond to a 'fields' argument by returning a (possibly) partial
# representation of our objects.  If we get a bare '*', or no fields
# argument at all, we should return all fields.  We'll represent that
# internally with our fields arrayref being undef.
#
# We'll make sure there are no internal fields in the list, with
# leading underscores.  Private things should remain private.
sub _convert_fields_arg {
    my ($args) = @_;

    my @fields = map { split /,/ }
      grep { defined $_ && $_ } $args->get('fields');
    return undef if !scalar @fields;
    return undef if scalar @fields == 1 && $fields[0] eq '*';
    return [ grep { $_ !~ /^_/; } @fields ];
}

# Assemble the representation that the caller has requested.  An
# undefined $fields parameter corresponds to "all the fields".  If the
# caller has requested things that aren't in the normal frozen
# representation of the object, but correspond with public methods
# that the class provides, then we should add them in.
sub _freeze_object {
    my ( $vc, $fields ) = @_;

    my $obj;
    my $methods = $vc->supported_methods();
    if ( defined $fields ) {
        my $tmp_obj = $vc->serialize();

        # The repository root is our unique key, so always return it.
        $obj->{'repository_root'} = $tmp_obj->{'repository_root'};
        for my $field (@$fields) {
            if ( $field eq 'tasks' ) {
                $obj->{$field} = _user_tasks( $tmp_obj->{'repository_root'} );
            }
            elsif ( exists $tmp_obj->{$field} ) {
                $obj->{$field} = $tmp_obj->{$field};
            }
            elsif ( ( grep { $_ eq $field } @$methods ) && $vc->can($field) ) {
                $obj->{$field} = $vc->$field();
            }
        }
    }
    else {
        $obj = $vc->serialize();

        for my $func (@$methods) {
            $obj->{$func} = $vc->$func()
              if $vc->can($func);
        }
        $obj->{'tasks'} = _user_tasks( $vc->{'repository_root'} );
    }

    return _clean_urls($obj);
}

# If a user does not have shell access turned on, we need to remove
# ssh: URLs from the representations we pass back.
#
# We perform this filtering in the API layer rather than in the
# objects themselves because a version control repository has no need
# to know whether a user has shell access turned on.  We separate
# concerns, and integrate here at the last moment.
sub _clean_urls {
    my ($obj) = @_;

    return $obj unless defined $obj->{'clone_urls'};

    my $shell = Cpanel::Shell::get_shell();
    return $obj
      if $shell ne $Cpanel::Shell::NO_SHELL;

    for my $group ( keys %{ $obj->{'clone_urls'} } ) {
        $obj->{'clone_urls'}{$group} = [ grep { !/^ssh:/ && $_ } @{ $obj->{'clone_urls'}{$group} } ];
    }
    return $obj;
}

# The user task queue may have something related to a repository; the
# task in question should have a 'repository_root' argument, which
# we'll use as the trigger to add it to our representation.
sub _user_tasks {
    my ($repo_root) = @_;

    my $tasks = [];

    Cpanel::LoadModule::load_perl_module('Cpanel::UserTasks');

    my $ut = Cpanel::UserTasks->new();
    my $id = $ut->first();
    while ( $id ne '' ) {
        my $data = $ut->get($id);
        if (   $data->{'subsystem'} eq 'VersionControl'
            && $data->{'args'}{'repository_root'} eq $repo_root ) {
            $data->{'id'} = $id;
            push @$tasks, $data;
        }
        $id = $ut->next();
    }

    return $tasks;
}

1;
