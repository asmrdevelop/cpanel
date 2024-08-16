package Cpanel::StringFunc::File;

# cpanel - Cpanel/StringFunc/File.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::StringFunc::File

=cut

use Cpanel::Transaction::File::Raw ();
use Cpanel::StringFunc::Trim       ();
use Cpanel::Debug                  ();

our $VERSION            = '1.2';
our $DEFAULT_PERMISSION = 0644;

=head1 FUNCTIONS

=cut

# On a success addition this returns 1
# If the line already exists this returns 0
# On failure this returns undef
sub addlinefile {
    my ( $file, $lines_ar ) = @_;

    $lines_ar = [$lines_ar] if !ref $lines_ar;

    #TODO: Should this have the same existence check as the others?
    my $trans        = _get_trans($file);
    my $modified     = 0;
    my $contents_ref = $trans->get_data();
    my $has_contents = length $$contents_ref;

    $$contents_ref .= "\n" if $has_contents && substr( $$contents_ref, -1 ) ne "\n";
    foreach my $line (@$lines_ar) {
        if ( !$has_contents || ( index( $$contents_ref, "$line\n" ) != 0 && index( $$contents_ref, "\n$line\n" ) == -1 ) ) {
            $modified = 1;
            $$contents_ref .= "$line\n";
        }
    }
    return $modified ? _save_transaction_or_log($trans) : _abort_transaction_or_log($trans);
}

# On a success removal this returns 1
# If the line already removed this returns 0
# On failure this returns undef
sub remlinefile {
    my ( $file, $match_lines_ar, $matchtype ) = @_;
    if ( !$file || !$match_lines_ar ) {
        Cpanel::Debug::log_invalid('remlinefile requires: file, match_line');
        return;
    }

    #TODO: Remove this check in favor of opening the file non-O_CREAT.
    elsif ( !-e $file ) {
        Cpanel::Debug::log_warn("file $file does not exist.");
        return;
    }

    $match_lines_ar = [$match_lines_ar] if !ref $match_lines_ar;

    $matchtype ||= 'begin';

    my $trans        = _get_trans($file);
    my $contents_ref = $trans->get_data();
    my $changed      = 0;
    substr( $$contents_ref, 0, 0, "\n" );
    foreach my $match_line (@$match_lines_ar) {
        Cpanel::StringFunc::Trim::ws_trim( \$match_line );
        my $match_regex = ( $matchtype eq 'begin' ? qr/\n[ \t]*\Q$match_line\E[^\n]*/ : qr/\n[ \t]*\Q$match_line\E(?=[:\n]+)/ );
        $changed += ( $$contents_ref =~ s{$match_regex}{}g );
    }
    if ($changed) {
        substr( $$contents_ref, 0, 1, '' );
        return _save_transaction_or_log($trans);
    }
    return _abort_transaction_or_log($trans);
}

# On a success removal this returns 1
# If the line already removed this returns 0
# On failure this returns undef
sub remlinefile_strict {
    my ( $file, $match_regex ) = @_;

    if ( !$file || !$match_regex ) {
        Cpanel::Debug::log_invalid('remlinefile_strict requires: file, match_regex');
        return;
    }

    #TODO: Remove this check in favor of opening the file non-O_CREAT.
    elsif ( !-e $file ) {
        Cpanel::Debug::log_warn("file $file does not exist.");
        return;
    }

    my $trans        = _get_trans($file);
    my $contents_ref = $trans->get_data();
    my @CFILE        = split( "\n", $$contents_ref, -1 );    # -1 preserves trailing new lines
    if ( grep ( /$match_regex/, @CFILE ) ) {                 # no need to remove it if its not there
        $trans->set_data( \join( "\n", grep( !/$match_regex/, @CFILE ) ) );
        return _save_transaction_or_log($trans);
    }
    return _abort_transaction_or_log($trans);
}

=head2 replacelinefile( PATH, MATCH_REGEXP, REPLACEMENT_STR )

Replace lines that match a given regular expression. Returns
the number of lines updated.

Note that REPLACEMENT_STR must be a string. Backreferences won’t
work normally; if you need that, use L<overload>. See this function’s
tests for an example.

On failure or nonexistence this returns undef and logs to the
system’s main log. An unfortunate effect of this is that the return
doesn’t distinguish between nonexistence of the file and an actual
failure.

TODO: Create variants on this module’s functions that allow for that
distinction.

=cut

sub replacelinefile {
    my ( $file, $match_regex, $replacement ) = @_;

    if ( !$file || !$match_regex || !$replacement ) {
        Cpanel::Debug::log_invalid('replacelinefile requires: file, match_regex, replacement');
        return undef;
    }

    #TODO: Remove this check in favor of opening the file non-O_CREAT.
    elsif ( !-e $file ) {
        Cpanel::Debug::log_warn("file $file does not exist.");
        return undef;
    }

    my $trans = _get_trans($file);

    my $contents_ref = $trans->get_data();
    my @CFILE        = split( "\n", $$contents_ref, -1 );    # -1 preserves trailing new lines

    my $replaced;
    for (@CFILE) {
        $replaced += s<$match_regex><$replacement>;
    }

    if ($replaced) {
        $trans->set_data( \join( "\n", @CFILE ) );
        return _save_transaction_or_log($trans) && $replaced;
    }

    return _abort_transaction_or_log($trans);
}

#----------------------------------------------------------------------

sub _current_perms_or_default {
    my ($file) = @_;
    my ( $mode, $uid, $gid ) = ( stat($file) )[ 2, 4, 5 ];
    $mode = $DEFAULT_PERMISSION if !defined $mode;
    return ( $mode & 07777, $uid, $gid );
}

sub _save_transaction_or_log {
    my ($trans) = @_;
    my ( $save_ok, $save_msg ) = $trans->save_and_close();
    Cpanel::Debug::log_warn($save_msg) if !$save_ok;
    return $save_ok;
}

sub _abort_transaction_or_log {
    my ($trans) = @_;
    my ( $abort_ok, $abort_msg ) = $trans->abort();
    Cpanel::Debug::log_warn($abort_msg) if !$abort_ok;
    return 0;
}

sub _get_trans {
    my ($file) = @_;
    my ( $current_perms, $current_uid, $current_gid ) = _current_perms_or_default($file);
    return Cpanel::Transaction::File::Raw->new( 'path' => $file, 'permissions' => $current_perms, ( defined $current_uid ? ( 'ownership' => [ $current_uid, $current_gid ] ) : () ) );
}

1;
