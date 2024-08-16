package Cpanel::FileUtils::RaceSafe::SQLite;

# cpanel - Cpanel/FileUtils/RaceSafe/SQLite.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::FileUtils::RaceSafe::SQLite - Race-safe SQLite schema setup

=head1 SYNOPSIS

    use Cpanel::FileUtils::RaceSafe::SQLite;

    my $safe_obj = Cpanel::FileUtils::RaceSafe::SQLite->new(
        path => '/path/to/it',
        dbi_options => { .. },
    );

    my $dbh = $safe_obj->dbh();

    #Initialize the schema via $dbh.

    #...then do ONE of these. See the base class for more information:
    $safe_obj->install();
    $safe_obj->install_unless_exists();
    $safe_obj->force_install();

    #This unlink()s the temp file:
    undef $safe_obj;

    #NOTE: $dbh is now read-only since the temp file is gone.
    #You probably shouldn’t use it anyway.

=head1 DESCRIPTION

This module implements L<Cpanel::FileUtils::RaceSafe::Base> for SQLite.
(This was actually the original use case for that module; the base class was
factored out for other potential uses.) The constructor’s C<dbi_options>
parameter contains the arguments that should go into creating the
temporary DBI file via cPanel’s L<Cpanel::DBI::SQLite> module.

Note that the underlying SQLite file will be opened with at least the
C<OPEN_CREATE> flag; see L<DBD::SQLite>’s documentation for other flags that
might be useful to pass in.

=cut

use strict;

use Cpanel::DBI::SQLite ();

use parent qw(
  Cpanel::FileUtils::RaceSafe::Base
);

sub dbh {
    my ($self) = @_;

    return $self->{'_dbh'};
}

sub _create_file {
    my ( $self, $tmp_file, %opts ) = @_;

    my %dbi_opts = $opts{'dbi_options'} ? @{ $opts{'dbi_options'} } : ();

    if ( exists $dbi_opts{'sqlite_open_flags'} ) {
        $dbi_opts{'sqlite_open_flags'} |= DBD::SQLite::OPEN_CREATE();
    }

    $self->{'_dbh'} = Cpanel::DBI::SQLite->connect(
        {
            db => $tmp_file,
            %dbi_opts,
        }
    );

    return;
}

1;
