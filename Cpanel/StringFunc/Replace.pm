package Cpanel::StringFunc::Replace;

# cpanel - Cpanel/StringFunc/Replace.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug                  ();
use Cpanel::Transaction::File::Raw ();

=encoding utf-8

=head1 NAME

Cpanel::StringFunc::Replace - Functions for replacing strings in text

=cut

#### replaces regsrep() ##

=head2 regex_rep_str( $string, $regex, $errbuf )

Used to modify a string using regular expressions.  Handy if you
have multiple regex that you want iteravely execute on it.

=over 2

=item Input

=over 4

=item I<scalar> (string)

Input string you want to modify.

=item I<scalar> (hash reference or array ref of hash references)

You can pass two kinds of data; array of hash references, or a single hash reference.
Each hash reference must contain a key and a value.  Each key/value pair must be
compatible for use by s///.  As such, the search and replace first tries to match
the key, then replaces the match with the supplied value.

If you pass in an array of hash references, it will use each hash in the order in which
it was passed.  Of course, the order in which a key is accessed within each of the
hashes cannot be guaranteed.

=item I<scalar> (optional hash reference)

This is an optional hash reference that the function will store search/replace errors
(if any).  If there's an error, the following key/value pairs will be stored: error,
find, replace.

The key `error' contains the scalar error message as defined by $@.
The key `find' contains the scalar search string that caused the error.
Finally, the key `replace', contains the scalar replace string that would have
been used if it was successful.

=back

=item Output

Returns a modified (or unmodified if nothing matches) string; even on error.

=back

=cut

sub regex_rep_str {
    my ( $string, $regex_ref, $error_hr ) = @_;

    for my $hash ( ref $regex_ref eq 'ARRAY' ? @{$regex_ref} : ($regex_ref) ) {
        next if ref $hash ne 'HASH';
        for my $pair ( keys %{$hash} ) {
            eval qq(\$string =~ s{\$pair}{$hash->{$pair}}go;);    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
            $error_hr->{$string} = {
                'error'   => $@,
                'find'    => $pair,
                'replace' => $hash->{$pair},
              }
              if $@
              && ref $error_hr eq 'HASH';
        }
    }

    return $string;
}

=head2 regsrep( $file, $old, $new, $useregex, $search $replace )

Searches a file for matching patterns and replaces either the entire line,
or specific portions of it.  All modifications are modify the file in-place.
Finally, all newlines and blank lines are skipped and cannot be modified.

DEPRECATED! Please use Cpanel::FileUtils::regex_rep_file() instead.

=over 2

=item Input

=over 4

=item I<scalar> (string)

Path to file that will be modified

=item I<scalar> (string)

This argument acts as a key to determine which line (or lines) will be modified.
The string must be suitable for use by m//.  If $useregex is a true value, then it
must also be suitable for use by s///.

=item I<scalar> (string)

If this argument is -1, then the matching line will be removed from the file.
If $useregex is a true value, then this string must be suitable for use by
m//, and any $search and $replace arguments will be ignored.
Finally, if $useregex is a false value, then the entire matching line is replace
with $new.

=item I<scalar> (string)

The $useregex argument instructs this routine to modify a line in place, as opposed
to replacing the entire line with the $new argument.  This is accomplished by issuing
a s///.  As mentioned above, this will also prevent a line from using $search and
$replace arguments.

=item I<scalar> (string)

The $search argument is defined (and $useregex is not), then it will be used in
conjunction with the $replace argument to execute a s///.  Thus, the string should
be compatibile.

=item I<scalar> (string)

Used with $search to modify a string on a line.

=back

=item Output

This routine will return 1 on success.  It will return undef (or 0) on the following
errors: unable to find find input file, unable to open and lock file for modification,
and finally, unable to close and unlock file.

=back

=cut

sub regsrep {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $file, $old, $new, $useregex, $search, $replace ) = @_;
    my @CFILE;
    if ( !-e $file ) {
        Cpanel::Debug::log_warn("Could not find $file");
        return;
    }
    my $trans = eval { Cpanel::Transaction::File::Raw->new( 'path' => $file, restore_original_permissions => 1 ); };
    if ( !$trans ) {
        Cpanel::Debug::log_warn("Could not open “$file” for editing: $!");
        return;
    }
    my $data     = $trans->get_data();
    my $modified = 0;
    foreach ( split( m/^/, $$data ) ) {
        if ( $_ =~ m/^\s*$/ || $_ eq "\n" || $_ eq "\r\n" ) {
            push @CFILE, $_;
        }
        elsif ( $_ =~ m{$old} ) {
            $modified = 1;
            next if $new eq '-1';
            my $mnew = $new;

            my $result1 = $1;
            my $result2 = $2;

            if ( defined $result1 ) {
                $mnew =~ s{\$1}{$result1}g;
                if ( defined $result2 ) {
                    $mnew =~ s{\$2}{$result2}g;
                }
            }

            if ($search) {
                $mnew =~ s{$search}{$replace}g;
            }

            if ($useregex) {
                $mnew = $_;
                $mnew =~ s{$old}{$new}g;
                $mnew =~ tr{\n}{}d;
            }
            push @CFILE, "$mnew\n";
        }
        else {
            push @CFILE, $_;
        }
    }
    my $contents = join( '', @CFILE );
    if ( $modified && !length $contents ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Refusing to modify or write empty file $file");
    }

    if ($modified) {
        $trans->set_data( \$contents );
        my ( $ok, $err ) = $trans->save_and_close();
        if ( !$ok ) {
            Cpanel::Debug::log_warn("Could not save “$file”: $err");
            return 0;
        }

    }
    else {
        my ( $ok, $err ) = $trans->close();
        if ( !$ok ) {
            Cpanel::Debug::log_warn("Could not close “$file”: $err");
            return 0;
        }

    }
    return 1;
}

1;
