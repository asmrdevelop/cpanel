package Whostmgr::Transfers::Session::Preflight::RemoteRoot::SimpleParse;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/SimpleParse.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Preflight::RemoteRoot::SimpleParse

=head1 DESCRIPTION

This is an intermediate class that subclasses
L<Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base> with enough
logic to facilitate backup/restoration from a single JSON structure.

Use this with backup & restore modules that subclass
L<Whostmgr::Config::Backup::Base::JSON> and
L<Whostmgr::Config::Restore::Base::JSON>.

=head1 REQUIRED SUBCLASS METHODS

Subclasses of this class must provide all methods that
L<Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base> requires,
B<EXCEPT> C<_parse_analysis_commands()>.

=head1 OPTIONAL SUBCLASS METHODS

Subclasses of this class may provide:

=over

=item * C<_errors_and_warnings($remote_data)> - Returns two array
references: one for errors, and the (optional) other for warnings.
C<$remote_data> is as given to C<_parse_analysis_commands()>.

=back

=cut

#----------------------------------------------------------------------

use parent 'Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base';

use Cpanel::LoadModule ();

use constant _errors_and_warnings => ( [], [] );

#----------------------------------------------------------------------

sub _parse_analysis_commands ( $self, $remote_data ) {

    my $module_name = $self->_module_name();

    # Take the output of the --query-module-info in get_analysis_commands() for parsing response data out of
    my $query   = $remote_data->{ $self->_analysis_key() } || '';
    my $version = "";

    my $backup_ns = $self->_BACKUP_NAMESPACE();

    my @lines = split( /\n/, $query );
    foreach my $line (@lines) {
        if ( $line =~ m/^\Q$backup_ns\E: \Q$module_name\E_Version=(.+)$/ ) {
            $version = $1;
        }
    }

    my $backup_module = "Whostmgr::Config::Backup::System::$module_name";
    Cpanel::LoadModule::load_perl_module($backup_module);

    # Get local version
    my $local_version = $backup_module->query_module_info();
    $local_version =~ s/.+_Version=// or die "$backup_module - Unexpected query_module_info() return: “$local_version”!";

    my @errors;

    if ( !$version || $version =~ m<unknown>i ) {
        push @errors, $self->_locale()->maketext( 'The remote server lacks the ability to export its “[_1]” configuration.', $module_name );
    }

    my ( $errs_ar, $warns_ar ) = $self->_errors_and_warnings($query);

    push @errors, @$errs_ar if $errs_ar;

    $warns_ar ||= [];

    return {
        errors                          => \@errors,
        warnings                        => $warns_ar,
        "Local_${module_name}_Version"  => $local_version || 'Unknown',
        "Remote_${module_name}_Version" => $version       || 'Unknown',
    };
}

1;
