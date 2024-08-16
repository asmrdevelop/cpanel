package Cpanel::Locale::Utils::Charmap;

# cpanel - Cpanel/Locale/Utils/Charmap.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::ArrayFunc::Uniq ();

# Wrapper for legacy code, this does NOT exclude charmaps which are incompatible with iconv
sub get_charmap_list ( $root_says_to_make_symlinks = 0, $no_aliases = 0 ) {    ## no critic(Subroutines::ProhibitManyArgs)
    my $args = { 'iconv' => 0, 'unpreferred_aliases' => ( $no_aliases ? 0 : 1 ) };
    if ($root_says_to_make_symlinks) {
        make_symlinks();
    }
    return @{ get_charmaps($args) };
}

sub get_charmaps ( $args = {} ) {
    _validate_args( $args, { map { $_ => 1 } qw( iconv unpreferred_aliases ) } );

    my ( $iconv, $unpreferred_aliases ) = @{$args}{ 'iconv', 'unpreferred_aliases' };
    $iconv //= 1;    # Provide iconv compatibility by default.

    my %charset_aliases   = _get_charset_aliases();
    my %excluded_charmaps = _get_excluded_charmaps( $iconv, $unpreferred_aliases );
    my @raw_charmaps      = ( qw(utf-8 us-ascii), _get_filesystem_charmaps(), ( $unpreferred_aliases ? %charset_aliases : ( values %charset_aliases ) ) );
    my %charmaps;
    for my $cm (@raw_charmaps) {
        $cm =~ tr{A-Z}{a-z};
        my $copy     = $cm;
        my $stripped = ( $copy =~ tr{_.-}{}d );    #prefer "utf-8" over "utf8"
        if ( !exists( $excluded_charmaps{$cm} ) && ( !exists( $charmaps{$copy} ) || $stripped ) ) {
            $charmaps{$copy} = $cm;
        }
    }

    return [ sort ( Cpanel::ArrayFunc::Uniq::uniq( values %charmaps ) ) ];
}

sub make_symlinks {
    return unless $> == 0;
    my %charset_aliases = _get_charset_aliases();
    my $charmapsdir     = _get_charmaps_dir();

    # At least one alias is an alias-of-an-alias, requiring a
    # symlink-of-a-symlink on disk. It's not possible to predetermine the
    # correct symlink creation order without assuming which real files exist
    # on disk, so to keep it completely dynamic it's easy enough to loop
    # through the alias-creation twice to ensure both levels of aliases are
    # created.
    for my $loop ( 1 .. 2 ) {
        for my $key ( keys %charset_aliases ) {
            lstat("$charmapsdir/$key.gz");    # unpreferred
            if ( -e _ ) {
                lstat("$charmapsdir/$charset_aliases{$key}.gz");    # preferred
                if ( !-e _ && !-l _ ) {
                    symlink( "$charmapsdir/$key.gz", "$charmapsdir/$charset_aliases{$key}.gz" );    # unpreferred -> preferred
                }
            }
            elsif ( !-l _ && -e "$charmapsdir/$charset_aliases{$key}.gz" ) {                        # preferred
                symlink( "$charmapsdir/$charset_aliases{$key}.gz", "$charmapsdir/$key.gz" );        # preferred -> unpreferred
            }
        }
    }
    return 1;
}

sub _validate_args ( $args, $possible_args ) {

    # Currently only looking for unknown/typo'd arg keys
    if ( my @bad_args = grep { !$possible_args->{$_} } keys %{$args} ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create_raw( 'InvalidParameters', 'The following arguments are invalid: ' . join ', ', @bad_args );
    }
}

sub _get_charmaps_dir {
    state $charmaps_dir = -e '/usr/local/share/i18n/charmaps' ? '/usr/local/share/i18n/charmaps' : '/usr/share/i18n/charmaps';
    return $charmaps_dir;
}

sub _get_charset_aliases {

    # %CHARSET_ALIASES from MIME::Charset v1.008
    return (    # unpreferred => preferred
        'ASCII'             => 'US-ASCII',
        'BIG5-ETEN'         => 'BIG5',
        'CP1251'            => 'WINDOWS-1251',
        'CP1252'            => 'WINDOWS-1252',
        'CP936'             => 'GBK',
        'CP949'             => 'KS_C_5601-1987',    # Note: same preferred as KS_C_5601
        'EUC-CN'            => 'GB2312',
        'KS_C_5601'         => 'KS_C_5601-1987',    # Note: same preferred as CP949
        'SHIFTJIS'          => 'SHIFT_JIS',
        'SHIFTJISX0213'     => 'SHIFT_JISX0213',
        'UNICODE-1-1-UTF-7' => 'UTF-7',             # RFC 1642 (obs.)
        'UTF8'              => 'UTF-8',
        'UTF-8-STRICT'      => 'UTF-8',             # Perl internal use
        'HZ'                => 'HZ-GB-2312',        # RFC 1842
        'GSM0338'           => 'GSM03.38',
    );
}

sub _get_iconv_blacklist {

    # These are not suitable for use as iconv input or output encodings
    return (
        'big5-eten',
        'bs_viewdata',
        'csa_z243.4-1985-gr',
        'gsm03.38',
        'gsm0338',
        'hz',
        'hz-gb-2312',
        'invariant',
        'iso_10646',
        'iso_646.basic',
        'iso_646.irv',
        'iso_6937-2-25',
        'iso_6937-2-add',
        'iso_8859-1,gl',
        'iso_8859-supp',
        'jis_c6220-1969-jp',
        'jis_c6229-1984-a',
        'jis_c6229-1984-b-add',
        'jis_c6229-1984-hand',
        'jis_c6229-1984-hand-add',
        'jis_c6229-1984-kana',
        'jis_x0201',
        'jus_i.b1.003-mac',
        'jus_i.b1.003-serb',
        'ks_c_5601',
        'ks_c_5601-1987',
        'nats-dano-add',
        'nats-sefi-add',
        'nextstep',
        'sami',
        'sami-ws2',
        't.101-g2',
        't.61-7bit',
        'unicode-1-1-utf-7',
        'utf-8-strict',
        'videotex-suppl',
    );
}

sub _get_filesystem_charmaps {
    state @filesystem_charmaps;
    return @filesystem_charmaps if @filesystem_charmaps;

    my $charmapsdir = _get_charmaps_dir();
    if ( opendir my $charmaps_dh, $charmapsdir ) {
        @filesystem_charmaps = map { m{\A([^.].*)[.]gz\z}xms ? $1 : () } readdir $charmaps_dh;
        closedir $charmaps_dh;
    }
    return @filesystem_charmaps;
}

sub _get_excluded_charmaps ( $iconv, $unpreferred_aliases ) {
    my %excluded;
    if ($iconv) {
        for my $bl ( _get_iconv_blacklist() ) {
            $excluded{$bl} = 1;
        }
    }
    if ( !$unpreferred_aliases ) {
        my %charset_aliases = _get_charset_aliases;
        for my $alias ( keys %charset_aliases ) {
            $alias =~ tr{A-Z}{a-z};
            $excluded{$alias} = 1;
        }
    }
    return %excluded;
}

1;

__END__
=pod

=head1 NAME

C<Cpanel::Locale::Utils::Charmap>

=head1 DESCRIPTION

Utility module related to character maps (encodings) installed on the system.

=head1 FUNCTIONS

=head2 get_charmaps( { unpreferred_aliases => 0, iconv => 1 } )

Returns a sorted, de-duplicated array reference of installed character maps on the system.
This is intended to replace C<get_charmap_list>.

This excludes unpreferred aliases and charmaps which are not compatible with C<iconv> by default.

Optional named arguments are passed in a hash reference.

=head3 ARGUMENTS

=over

=item iconv

Default value is 1 (true) which excludes character maps in the output which are not suitable for use as input or output options with the C<iconv> system.

=item unpreferred_aliases

Default value is 0 (false) which excludes unpreferred aliases (see MIME::Charset) in the output list.

=back

=head3 THROWS

=over

=item C<Cpanel::Exception::InvalidParameters>

An exception will be thrown if any unknown arguments are passed in.

=back

=head2 make_symlinks()

Creates symlinks between preferred and unpreferred aliases in the system charmaps directory.
This only works if the current EUID is 0 (root).

Returns true after creating the symlinks, otherwise returns false.

=head3 ARGUMENTS

None.

=head2 get_charmap_list( $root_says_to_make_symlinks, $no_aliases )

DEPRECATED: use C<get_charmaps()> instead.
A wrapper around C<get_charmaps()> for legacy code.
Returns a list of charmaps.

NOTE: This does not exclude unpreferred charmaps (aliases) by default, and is not capable of excluding charmaps which are incompatible with iconv.

Optional arguments are positional.

=head3 ARGUMENTS

=over

=item root_says_to_make_symlinks

Default value is 0 (false).
A true value creates symlinks between preferred and unpreferred aliases in the system charmaps directory.
This only works if the current EUID is 0 (root).
DEPRECATED: use make_symlinks() instead.

=item no_aliases

Default value is 0 (false) which includes unpreferred aliases (see MIME::Charset) in the output list.

=back

=cut
