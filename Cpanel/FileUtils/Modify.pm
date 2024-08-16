package Cpanel::FileUtils::Modify;

# cpanel - Cpanel/FileUtils/Modify.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Transaction::File::Raw ();

# Case 92825 - Need to add or remove lines from a file but use
# the overwrite method for final output.
my $DEFAULT_PERMS = 0600;

=head1 NAME

Cpanel::FileUtils::Modify - Modify the contents of a file

=head1 SYNOPSIS

    use Cpanel::FileUtils::Modify ();

    addline( '/path/to/a/file', 'Hello There', 0600 );
    addline( '/path/to/a/file', 'Hello World' );

    remlinefile( '/path/to/a/file', 'There' );
    remlinefile( '/path/to/a/file', 'Hello', 'begin');

    my $updated = Cpanel::FileUtils::Modify::match_replace(
        '/path/to/a/file',
        [
            # string replacement type, "thing=THIS" becomes "#thing=THAT"
            { match => qr/^thing=.*$/m, replace => '#thing=THAT' },

            # code-ref replacement type, "THING=this" becomes "##THING=this"
            { match => qr/^(THING=.*)$/m, replace_cr => sub { "##$1" } },

            # delete a matched line and the next line-break if it exists (don't leave behind an empty line)
            { match => qr/^DELETEME.*\R?/m, replace => q{} },

            { ... },
        ]
    );

=head1 DESCRIPTION

This module contains functions which are used to add, modify, or remove lines in
a file.

=head1 FUNCTIONS

=head2 addline( $fname, $line, $perms )

Add a single line to a file.

=head3 ARGUMENTS

=over

=item $fname - string

Required. The path to a file.

=item $line - string

Required. A string containing a line to add to the file, excluding line break.

=item $perms - number

Optional. A number (usually represented in octal form) to set the file
permissions (mode) to. If this value is not present then the existing
permissions are preserved. The default value for new files is 0600.

=back

=head3 RETURNS

Always returns 1.

=head3 EXCEPTIONS

When the file is unable to be saved or closed.

=cut

# modeled after Cpanel::TextDB::addline
sub addline {
    my ( $fname, $line, $perms ) = @_;

    my $tran_obj = _get_trans_obj( $fname, $perms );
    my @output;
    my $inserted_new_line_after_comment = 0;
    foreach my $xline ( split( /\n/, ${ $tran_obj->get_data() } ) ) {
        if ( !$inserted_new_line_after_comment && $xline !~ /^#/ ) {
            push @output, $line;
            $inserted_new_line_after_comment = 1;
        }
        push @output, $xline;
    }
    push @output, $line if !$inserted_new_line_after_comment;

    my $buffer = join( "\n", @output ) . "\n";
    $tran_obj->set_data( \$buffer );
    $tran_obj->save_and_close_or_die();

    return 1;
}

=head2 remlinefile( $fname, $match_line, $matchtype )

Remove all lines in a file which match a string.

=head3 ARGUMENTS

=over

=item $fname - string

Required. The path to a file.

=item $match_line - string

Required. A line of text to remove from the file. Whitespace before and after
this string in the file is allowed.

=item $matchtype - string

Optional. A string value representing an optional match type which affects how
the match string is anchored:

=over

=item begin

Anchors the match string to the beginning of a line and not the end. In other
words the match string acts as a prefix and any line with that prefix will be
deleted.

=back

=back

=head3 RETURNS

Always returns 1.

=head3 EXCEPTIONS

When the file is unable to be saved or closed.

=cut

# modeled after Cpanel::StringFunc::File::remlinefile
sub remlinefile {
    my ( $fname, $match_line, $matchtype ) = @_;

    my $tran_obj = _get_trans_obj($fname);
    my @lines    = split( /\n/, ${ $tran_obj->get_data() } );

    chomp $match_line;
    $match_line =~ s/^\s+//;
    $match_line =~ s/\s+$//;

    my $match_regex = ( defined $matchtype && $matchtype eq 'begin' ? qr/^\s*\Q$match_line\E\s*/ : qr/^\s*\Q$match_line\E\s*$/ );

    local $@;
    my @outlines = eval 'grep ( !/$match_regex/o, @lines );';    ## no critic qw(BuiltinFunctions::ProhibitStringyEval) -- String eval is to allow /o
    my $buffer   = join( "\n", @outlines ) . "\n";

    $tran_obj->set_data( \$buffer );
    $tran_obj->save_and_close_or_die();

    return 1;
}

=head2 match_replace( $fname, $substitutions_ar )

Modify a file based on a set of substitution items that contain regex matches
with either string or evaluated code-ref replacements.

=head3 ARGUMENTS

=over

=item $fname - string

Required. The path to a file.

=item $substitions_ar - array ref

Required. This array ref should contain zero or more hash refs with the
following keys and values:

=over

=item match => regex

Required. The value may be a regex pattern string or a compiled regex from the
qr// operator. This regex will be evaluated against the entire file contents,
so the 'm' regex modifier is recommended in addition to anchoring at the
beginning or end of the line as needed (e.g. qr/^something.*$/m). All
occurrences of the match will be replaced.

=item replace => string

This OR replace_cr is required. The value must be a string to use as the
replacement for a match.

=item replace_cr => code ref

This OR replace is required. The value must be a code ref (e.g. sub {}) that
will be executed without any arguments and must return a string to use as the
replacement for a match. Capture groups from the match regex can be used such
as $1, $2, etc.

=back

=back

=head3 RETURNS

The number of successful match and replace operations, or undef if the source
file didn't exist.

=head3 EXCEPTIONS

When the match option is not defined.

When neither replace or replace_cr options are defined in a substitution item.

When the replace and replace_cr options are defined in the same substutition
item.

When the file is unable to be saved or closed.

=cut

sub match_replace ( $fname, $substitutions_ar ) {
    return undef unless _exists($fname);

    my $transaction = _get_trans_obj($fname);
    my $data_sr     = $transaction->get_data;
    my $updated     = 0;
    foreach my $substitution_hr ( @{$substitutions_ar} ) {
        my ( $match, $replace, $replace_cr ) = @{$substitution_hr}{qw( match replace replace_cr )};
        die 'match must be defined' unless defined $match;
        my $have_replace    = defined $replace;
        my $have_replace_cr = ref $replace_cr ? 1 : 0;
        die 'replace and replace_cr are mutually exclusive' if $have_replace && $have_replace_cr;
        die 'Either replace or replace_cr must be defined' unless $have_replace || $have_replace_cr;
        if ($have_replace_cr) {
            $updated += ( $$data_sr =~ s/$match/$replace_cr->()/ge );
        }
        else {
            $updated += ( $$data_sr =~ s/$match/$replace/g );
        }
    }

    if ($updated) {
        $transaction->save_and_close_or_die;
    }
    else {
        $transaction->close_or_die;
    }

    return $updated;
}

sub _get_trans_obj {
    my ( $fname, $perms ) = @_;

    my ( $mode, $file_current_uid, $file_current_gid ) = ( stat($fname) )[ 2, 4, 5 ];
    my ($ownership);
    if ( defined $mode ) {
        if ( !defined $perms ) {
            $perms = $mode & 07777;
        }

        #
        # When running as root we need to preseve the gid on the file
        # This is especially important when making changes to
        # /etc/userdomains since it is only readable by the root
        # and the mail group.  See CPANEL-5899
        #
        # In v56 we changed the transaction object to
        # create a new file and rename it in place via
        # Cpanel::SafeFile::Replace::locked_atomic_replace_contents in
        # order to provide additional durability in the transaction
        # in the event the filesystem or system crashes during the
        # write.
        #
        # To ensure we retain the gid, we now check the current gid
        # of the file and if it does not match current EGID we add
        # an explict ownership flag to the Cpanel::Transaction::File::Raw
        # to ensure the new file gets the correct ownership before it
        # is renamed in place.
        #
        # For information on how this works please see
        # _set_permissions in Cpanel::Transaction::File::Base
        #
        if ( $> == 0 && $file_current_gid != 0 && $file_current_gid != ( split( m{ }, scalar $) ) )[0] ) {

            # If our EGID is not the same as file's current GID we need to set it
            # If we did not set ownership the new file will be written with the current EGID
            $ownership = [ $file_current_uid, $file_current_gid ];
        }
    }
    elsif ( !defined $perms ) {
        $perms = $DEFAULT_PERMS;
    }

    return Cpanel::Transaction::File::Raw->new(
        path        => $fname,
        permissions => $perms,
        ( $ownership ? ( ownership => $ownership ) : () )
    );
}

sub _exists ($path) {
    return -e $path;
}

1;
