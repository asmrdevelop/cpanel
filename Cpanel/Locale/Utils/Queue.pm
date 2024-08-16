package Cpanel::Locale::Utils::Queue;

# cpanel - Cpanel/Locale/Utils/Queue.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::DataStore             ();
use Cpanel::Locale::Utils::Paths  ();
use Cpanel::Locale::Utils::Legacy ();

sub get_newphrase_file {
    return '/usr/local/cpanel/locale/queue/new.yaml';
}

sub get_pending_file {
    return '/usr/local/cpanel/locale/queue/pending.yaml';
}

sub get_pending_skipped_dir {
    return '/usr/local/cpanel/locale/queue/pending/skipped';
}

sub get_pending_human_dir {
    return '/usr/local/cpanel/locale/queue/pending/human';
}

sub get_pending_mach_dir {
    return '/usr/local/cpanel/locale/queue/pending/machine';
}

sub get_staging_dir {
    return '/usr/local/cpanel/locale/queue/staging';
}

sub get_missing_dir {
    return '/usr/local/cpanel/locale/queue/missing';
}

sub get_missing_legacy_dir {
    return '/usr/local/cpanel/locale/queue/missing_legacy';
}

sub get_pending_file_list_for_locale {
    my ($locale_tag) = @_;
    return if $locale_tag =~ m{(?:\/|\.\.)};

    # this is in the order we'd want to put them in the lexicon so that a human key will overwrite a machine key
    return map { -e "$_/$locale_tag.yaml" ? "$_/$locale_tag.yaml" : () } get_pending_mach_dir(), get_pending_human_dir();
}

my $human_hr;
my $mach_hr;

sub get_best_available_pending_translation {
    my ( $locale_tag, $phrase ) = @_;
    return if $locale_tag =~ m{(?:/|\.\.)};

    my $best;
    my $ph = get_pending_human_dir() . "/$locale_tag.yaml";
    if ( -e $ph ) {
        if ( !exists $human_hr->{$locale_tag} ) {
            $human_hr->{$locale_tag} = Cpanel::DataStore::fetch_ref($ph);
        }

        if ( exists $human_hr->{$locale_tag}{$phrase} ) {
            $best = $human_hr->{$locale_tag}{$phrase};    # do not return() here so that both caches are created
        }
    }

    my $pm = get_pending_mach_dir() . "/$locale_tag.yaml";
    if ( -e $pm ) {
        if ( !exists $mach_hr->{$locale_tag} ) {
            $mach_hr->{$locale_tag} = Cpanel::DataStore::fetch_ref($pm);
        }

        if ( exists $mach_hr->{$locale_tag}{$phrase} ) {
            $best ||= $mach_hr->{$locale_tag}{$phrase};
        }
    }

    return $best if $best;
    return;
}

my $newphrase_file_hr;
my $pending_file_hr;

sub phrase_is_in_new {

    # did not unpack @_ for optimization since this function is so short and we only use one item in one place
    if ( !$newphrase_file_hr ) {
        $newphrase_file_hr = Cpanel::DataStore::fetch_ref( get_newphrase_file() );
    }
    return 1 if exists $newphrase_file_hr->{ $_[0] };
}

sub phrase_is_in_pending {

    # did not unpack @_ for optimization since this function is so short and we only use one item in one place
    if ( !$pending_file_hr ) {
        $pending_file_hr = Cpanel::DataStore::fetch_ref( get_pending_file() );
    }

    return 1 if exists $pending_file_hr->{ $_[0] };
    return;
}

sub phrase_is_in_queue {

    # did not unpack @_ for optimization since this function is so short and we only use one item in one place
    return 1 if phrase_is_in_new( $_[0] );
    return 1 if phrase_is_in_pending( $_[0] );
    return;
}

my $lex_hr;

sub get_location_of_key {
    my ( $locale_tag, $phrase ) = @_;

    if ( !$lex_hr || !exists $lex_hr->{$locale_tag} ) {
        $lex_hr->{$locale_tag} = Cpanel::DataStore::fetch_ref( Cpanel::Locale::Utils::Paths::get_locale_yaml_root() . "/$locale_tag.yaml" );
    }

    return 'lexicon' if exists $lex_hr->{$locale_tag}{$phrase} && ( $locale_tag eq 'en' || $lex_hr->{$locale_tag}{$phrase} );
    return 'lexicon' if Cpanel::Locale::Utils::Legacy::phrase_is_legacy_key($phrase);

    if ( phrase_is_in_pending($phrase) ) {
        get_best_available_pending_translation( $locale_tag, $phrase );    # this init's cache hashes
        return 'human'   if exists $human_hr->{$locale_tag}{$phrase} && $human_hr->{$locale_tag}{$phrase};
        return 'machine' if exists $mach_hr->{$locale_tag}{$phrase}  && $mach_hr->{$locale_tag}{$phrase};
        return 'queue';
    }

    # this would include /usr/local/cpanel/base/frontend/x3 and friends since we aren't using them
    return 'new/custom';
}

sub lexicon_key_is_arbitrary {
    my ($key) = @_;

    return if index( $key, '__' ) == 0;
    return 1 if length($key) >= 2 && index( $key, '_' ) == 0 && substr( $key, 1, 1 ) ne '_';

    my $location = get_location_of_key( 'en', $key );    # inits $lex_hr->{'en'} cache
    if ( $location eq 'lexicon' ) {
        return 1 if $lex_hr->{'en'}{$key} && $key ne $lex_hr->{'en'}{$key};
    }
    elsif ( phrase_is_in_pending($key) ) {               # inits $pending_file_hr cache
        return 1 if $pending_file_hr->{$key} && $key ne $pending_file_hr->{$key};
    }

    return;
}

sub get_lexicon_key_en_value {
    my ($key) = @_;

    return if index( $key, '__' ) == 0;

    if ( lexicon_key_is_arbitrary($key) ) {              # inits $lex_hr->{'en'} and $pending_file_hr caches
        return $lex_hr->{'en'}{$key} if exists $lex_hr->{'en'}{$key};
        return $pending_file_hr->{$key};
    }
    else {
        return if Cpanel::Locale::Utils::Legacy::phrase_is_legacy_key($key);
        return $key;
    }
}

sub get_queue_values {
    my ( $locale_tag, $phrase ) = @_;

    if ( phrase_is_in_pending($phrase) ) {
        get_best_available_pending_translation( $locale_tag, $phrase );    # this init's cache hashes

        my $hr = {};
        $hr->{'human'}   = $human_hr->{$locale_tag}{$phrase} if exists $human_hr->{$locale_tag}{$phrase} && $human_hr->{$locale_tag}{$phrase};
        $hr->{'machine'} = $mach_hr->{$locale_tag}{$phrase}  if exists $mach_hr->{$locale_tag}{$phrase}  && $mach_hr->{$locale_tag}{$phrase};
        return $hr;
    }

    return;
}

sub _clear_cache {
    $lex_hr            = undef;
    $human_hr          = undef;
    $mach_hr           = undef;
    $newphrase_file_hr = undef;
    $pending_file_hr   = undef;
}

1;
