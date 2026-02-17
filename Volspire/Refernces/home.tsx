import React, { useRef, useState, useCallback, useEffect } from 'react';
import { View, Text, StyleSheet, FlatList, TouchableOpacity, TextInput, ScrollView } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { SafeAreaView } from 'react-native-safe-area-context';
import { supabase } from '@/lib/supabase';
import Ionicons from '@expo/vector-icons/Ionicons';
import { router, useFocusEffect } from 'expo-router';
import { useAudio } from '@/context/AudioContext';
import SearchOverlay from '@/components/Search/SearchOverlay';
import { useModal } from '@/context/ModalContext';
import { useAuth } from '@/context/AuthContext';
import { Image as ExpoImage } from 'expo-image';
import TrackLayout from '@/components/HomePage/TrackLayout';

export default function Explore() {
  const { playTrack, loadQueue, currentTrack, isPlaying } = useAudio();
  const { openModal } = useModal();
  const { user } = useAuth();
  const [tracks, setTracks] = useState<any[]>([]);
  const [following, setFollowing] = useState<any[]>([]);
  const [autoPlayedTrack, setAutoPlayedTrack] = useState<string | null>(null);
  const [scrollPosition, setScrollPosition] = useState(0);
  const [screenHeight, setScreenHeight] = useState(0);
  const [hasInitialAutoPlay, setHasInitialAutoPlay] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [showSearchOverlay, setShowSearchOverlay] = useState(false);
  const [searchSuggestions, setSearchSuggestions] = useState<string[]>([]);
  const [recentSearches, setRecentSearches] = useState<string[]>([]);
  const [activeFilters, setActiveFilters] = useState<string[]>([]);
  const [selectedLocationFilters, setSelectedLocationFilters] = useState<string[]>([]);
  const [selectedOccupationFilters, setSelectedOccupationFilters] = useState<string[]>([]);
  const [selectedGenreFilters, setSelectedGenreFilters] = useState<string[]>([]);
  const scrollViewRef = useRef<ScrollView>(null);
  const searchInputRef = useRef<TextInput>(null);
  // Fetch tracks from Supabase on mount
useEffect(() => {
  const fetchTracksWithUsernames = async () => {
    // Join tracks with users to get username - explicitly select credits and metadata JSONB columns
    const { data, error } = await supabase
      .from('tracks')
      .select('track_id, title, description, audio_url, visual_url, cover_url, visibility, created_at, updated_at, created_by, credits, metadata, users:created_by(user_id, profile_image_url, username)')
      .order('created_at', { ascending: false });
    if (error) {
      console.error('Error fetching tracks:', error);
    } else if (data) {
      // Attach username and profile_image_url to each track for easy access
      const tracksWithUsername = data.map((track: any) => ({
        ...track,
        profile_image_url: track.users?.profile_image_url || '',
        artist: track.users?.username || 'Unknown',
      }));
      console.log('Sample track data:', tracksWithUsername[0]); // Debug log
      setTracks(tracksWithUsername);
      // Load all tracks into the audio queue without auto-playing
      loadQueue(tracksWithUsername, 0, false);
    }
  };
  fetchTracksWithUsernames();
}, []);

// Fetch following users
const fetchFollowing = useCallback(async () => {
  if (!user?.id) return;

  const { data, error } = await supabase
    .from('user_relationships')
    .select('target_id, users:target_id(user_id, username, profile_image_url)')
    .eq('user_id', user.id)
    .eq('type', 'follow')
    .order('created_at', { ascending: false })
    .limit(20);

  if (error) {
    console.error('Error fetching following:', error);
  } else if (data) {
    setFollowing(data);
  }
}, [user?.id]);

// Initial fetch
useEffect(() => {
  fetchFollowing();
}, [fetchFollowing]);

// Refetch when screen comes into focus
useFocusEffect(
  useCallback(() => {
    fetchFollowing();
  }, [fetchFollowing])
);

  const filterItems = [
    { id: 'location', title: 'Location ▼', hasModal: true },
    { id: 'occupation', title: 'Occupation ▼', hasModal: true },
    { id: 'genre', title: 'Genre ▼', hasModal: true },
    { id: 'for-sale', title: 'For Sale', hasModal: false },
    { id: 'trending', title: 'Trending', hasModal: false },
    { id: 'recent', title: 'Recent', hasModal: false },
  ];

  const locationOptions = [
    { id: 'nyc', label: 'New York City', icon: 'location' },
    { id: 'la', label: 'Los Angeles', icon: 'location' },
    { id: 'chicago', label: 'Chicago', icon: 'location' },
    { id: 'atlanta', label: 'Atlanta', icon: 'location' },
    { id: 'miami', label: 'Miami', icon: 'location' },
    { id: 'london', label: 'London', icon: 'location' },
    { id: 'toronto', label: 'Toronto', icon: 'location' },
    { id: 'berlin', label: 'Berlin', icon: 'location' },
  ];

  const occupationOptions = [
    { id: 'producer', label: 'Producer', icon: 'musical-notes' },
    { id: 'vocalist', label: 'Vocalist', icon: 'mic' },
    { id: 'guitarist', label: 'Guitarist', icon: 'musical-note' },
    { id: 'drummer', label: 'Drummer', icon: 'radio' },
    { id: 'bassist', label: 'Bassist', icon: 'musical-note' },
    { id: 'dj', label: 'DJ', icon: 'disc' },
    { id: 'songwriter', label: 'Songwriter', icon: 'create' },
    { id: 'engineer', label: 'Sound Engineer', icon: 'settings' },
  ];

  const genreOptions = [
    { id: 'hip-hop', label: 'Hip Hop', icon: 'musical-notes' },
    { id: 'rnb', label: 'R&B', icon: 'musical-notes' },
    { id: 'pop', label: 'Pop', icon: 'musical-notes' },
    { id: 'rock', label: 'Rock', icon: 'musical-notes' },
    { id: 'jazz', label: 'Jazz', icon: 'musical-notes' },
    { id: 'electronic', label: 'Electronic', icon: 'musical-notes' },
    { id: 'acoustic', label: 'Acoustic', icon: 'musical-notes' },
    { id: 'indie', label: 'Indie', icon: 'musical-notes' },
    { id: 'reggae', label: 'Reggae', icon: 'musical-notes' },
    { id: 'country', label: 'Country', icon: 'musical-notes' },
  ];

  // Popular search suggestions
  const popularSuggestions = [
    'Hip Hop',
    'R&B', 
    'Pop',
    'Rock',
    'Jazz',
    'Electronic',
    'Acoustic',
    'Indie',
    'Rap',
    'Soul',
  ];

  // Auto-play disabled - tracks will only play when user interacts with them
  // useEffect(() => {
  //   const firstTrack = tracks.length > 0 ? tracks[0] : null;
  //   if (!hasInitialAutoPlay && firstTrack && !currentTrack) {
  //     console.log('Auto-playing first track on page load:', firstTrack.title);
  //     playTrack(firstTrack);
  //     setAutoPlayedTrack(firstTrack.id || firstTrack.track_id);
  //     setHasInitialAutoPlay(true);
  //   }
  // }, [tracks, currentTrack, hasInitialAutoPlay, playTrack]);

  // Update search suggestions based on query
  useEffect(() => {
    if (searchQuery.length > 0) {
      const suggestions = popularSuggestions.filter(suggestion =>
        suggestion.toLowerCase().includes(searchQuery.toLowerCase())
      );
      setSearchSuggestions(suggestions);
    } else {
      setSearchSuggestions(popularSuggestions);
    }
  }, [searchQuery]);

  // Auto-play handler for when tracks cross the threshold (Supabase only)
  const handleTrackAutoPlay = useCallback((trackId: string, shouldPlay: boolean) => {
    const track = tracks.find((song: any) => (song.id || song.track_id) === trackId);
    if (!track) return;

    if (shouldPlay && autoPlayedTrack !== trackId) {
      // Allow autoplay even if another track is playing (it will switch)
      console.log('🎵 Switching to auto-play track:', track.title);
      playTrack(track);
      setAutoPlayedTrack(trackId);
    }
  }, [tracks, playTrack, autoPlayedTrack]);

  const handleScroll = useCallback((event: any) => {
    const newScrollPosition = event.nativeEvent.contentOffset.y;
    setScrollPosition(newScrollPosition);
    // Uncomment for debugging: console.log('Scroll position:', newScrollPosition);
  }, []);

  const handleSearchInputPress = () => {
    setShowSearchOverlay(true);
  };

  const handleSearchOverlayClose = () => {
    setShowSearchOverlay(false);
  };

  const handleSearchSubmit = (query: string) => {
    setShowSearchOverlay(false);
    // Navigate to search results page
    router.push({
      pathname: '/search',
      params: { q: query }
    });
  };


  const handleFilterPress = (filterId: string) => {
    const filter = filterItems.find(f => f.id === filterId);
    
    if (filter?.hasModal) {
      // Open modal with appropriate data
      switch (filterId) {
        case 'location':
          openModal('filter', {
            title: 'Location',
            options: locationOptions,
            selectedOptions: selectedLocationFilters,
            onSelectionChange: handleLocationFilterChange,
            multiSelect: true,
          });
          break;
        case 'occupation':
          openModal('filter', {
            title: 'Occupation',
            options: occupationOptions,
            selectedOptions: selectedOccupationFilters,
            onSelectionChange: handleOccupationFilterChange,
            multiSelect: true,
          });
          break;
        case 'genre':
          openModal('filter', {
            title: 'Genre',
            options: genreOptions,
            selectedOptions: selectedGenreFilters,
            onSelectionChange: handleGenreFilterChange,
            multiSelect: true,
          });
          break;
      }
    } else {
      // Handle toggle filters (like "For Sale", "Trending", etc.)
      setActiveFilters(prev => {
        if (prev.includes(filterId)) {
          return prev.filter(id => id !== filterId);
        } else {
          return [...prev, filterId];
        }
      });
    }
  };


  const handleLocationFilterChange = (selectedIds: string[]) => {
    setSelectedLocationFilters(selectedIds);
  };

  const handleOccupationFilterChange = (selectedIds: string[]) => {
    setSelectedOccupationFilters(selectedIds);
  };

  const handleGenreFilterChange = (selectedIds: string[]) => {
    setSelectedGenreFilters(selectedIds);
  };

  const getFilterDisplayText = (filterId: string) => {
    const filter = filterItems.find(f => f.id === filterId);
    if (!filter) return '';

    switch (filterId) {
      case 'location':
        return selectedLocationFilters.length > 0 
          ? `Location (${selectedLocationFilters.length})` 
          : 'Location ▼';
      case 'occupation':
        return selectedOccupationFilters.length > 0 
          ? `Occupation (${selectedOccupationFilters.length})` 
          : 'Occupation ▼';
      case 'genre':
        return selectedGenreFilters.length > 0 
          ? `Genre (${selectedGenreFilters.length})` 
          : 'Genre ▼';
      default:
        return filter.title;
    }
  };

  const isFilterActive = (filterId: string) => {
    switch (filterId) {
      case 'location':
        return selectedLocationFilters.length > 0;
      case 'occupation':
        return selectedOccupationFilters.length > 0;
      case 'genre':
        return selectedGenreFilters.length > 0;
      default:
        return activeFilters.includes(filterId);
    }
  };

  return (
    <LinearGradient
      colors={['#1a1a1a', '#000']}
      style={styles.container}
    >
      <SafeAreaView style={styles.safeArea}>
        <ScrollView 
          ref={scrollViewRef}
          style={styles.scrollView}
          showsVerticalScrollIndicator={false}
          contentContainerStyle={styles.scrollContent}
          onScroll={handleScroll}
          scrollEventThrottle={16}
          onLayout={(event) => setScreenHeight(event.nativeEvent.layout.height)}
        >
          {/* Search Bar */}
          <TouchableOpacity style={styles.searchContainer} onPress={handleSearchInputPress} >
            <Ionicons name="search" size={20} color="#888" style={styles.searchIcon} />
            <Text style={styles.searchPlaceholder}>Search songs, artists, producers...</Text>
          </TouchableOpacity>

          {/* Filters */}
          <View style={styles.filtersContainer}>
            <ScrollView 
              horizontal 
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.filtersContent}
            >
              {filterItems.map((filter, index) => (
                <TouchableOpacity 
                  key={filter.id} 
                  style={[
                    styles.filterButton, 
                    isFilterActive(filter.id) && styles.activeFilter
                  ]}
                  onPress={() => handleFilterPress(filter.id)}
                  activeOpacity={0.7}
                >
                  <Text style={[
                    styles.filterText, 
                    isFilterActive(filter.id) && styles.activeFilterText
                  ]}>
                    {getFilterDisplayText(filter.id)}
                  </Text>
                </TouchableOpacity>
              ))}
            </ScrollView>
          </View>

          {/* Following Bar */}
          {following.length > 0 && (
            <View style={styles.followingContainer}>
              <View style={styles.followingWrapper}>
                <ScrollView 
                  horizontal 
                  showsHorizontalScrollIndicator={false}
                  contentContainerStyle={styles.followingContent}
                  style={styles.followingScroll}
                >
                  {following.map((item: any) => (
                    <TouchableOpacity 
                      key={item.target_id}
                      style={styles.followingItem}
                      onPress={() => router.push(`/user/${item.target_id}`)}
                    >
                      {item.users?.profile_image_url ? (
                        <ExpoImage
                          source={{ uri: item.users.profile_image_url }}
                          style={styles.followingAvatar}
                          contentFit="cover"
                        />
                      ) : (
                        <View style={[styles.followingAvatar, styles.followingAvatarPlaceholder]}>
                          <Ionicons name="person" size={20} color="#666" />
                        </View>
                      )}
                      <Text style={styles.followingUsername} numberOfLines={1}>
                        {item.users?.username || 'User'}
                      </Text>
                    </TouchableOpacity>
                  ))}
                </ScrollView>
                <TouchableOpacity 
                  style={styles.seeAllButton}
                  onPress={() => router.push('/pages/followers')}
                >
                  <Text style={styles.seeAllText}>All</Text>
                  <Ionicons name="arrow-forward" size={16} color="#42A0FF" />
                </TouchableOpacity>
              </View>
            </View>
          )}

          <Text style={{ color: '#fff', fontSize: 18, fontWeight: 'bold', margin: 12}}>Recommended for you</Text>

          {/* Grid */}
          <TrackLayout
            tracks={tracks}
          />
        </ScrollView>
      </SafeAreaView>

      {/* Search Overlay */}
      {showSearchOverlay && (
        <SearchOverlay
          visible={showSearchOverlay}
          onClose={handleSearchOverlayClose}
          onSearchSubmit={handleSearchSubmit}
          initialQuery={searchQuery}
        />
      )}
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  container: { 
    flex: 1,
  },
  safeArea: {
    flex: 1,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingBottom: 100,
  },
  searchContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#2c2c2cff',
    borderRadius: 8,
    marginHorizontal: 16,
    marginTop: 10,
    paddingHorizontal: 6,
    paddingVertical: 10,
  },
  searchIcon: {
    marginRight: 8,
  },
  searchPlaceholder: {
    flex: 1,
    color: '#888',
    fontSize: 16,
  },
  filtersContainer: {
    paddingHorizontal: 8,
    marginBottom: 16,
    marginTop: 16,
  },
  filtersContent: {
    gap: 8,
  },
  filterButton: {
    backgroundColor: '#1a1a1a',
    borderRadius: 4,
    paddingHorizontal: 16,
    paddingVertical: 10,
    fontSize: 14, fontWeight: '500',
  },
  activeFilter: {
    backgroundColor: '#333',
  },
  filterText: {
    color: '#ccc',
    fontSize: 13,
    fontWeight: '600',
  },
  activeFilterText: {
    color: '#fff',
    fontWeight: '600',
  },
  followingContainer: {
    paddingHorizontal: 16,
    marginBottom: 16,
  },
  followingWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  followingScroll: {
    flex: 1,
  },
  followingContent: {
    gap: 12,
    paddingRight: 16,
  },
  followingItem: {
    alignItems: 'center',
    width: 60,
  },
  followingAvatar: {
    width: 50,
    height: 50,
    borderRadius: 25,
    marginBottom: 6,
  },
  followingAvatarPlaceholder: {
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  followingUsername: {
    color: '#fff',
    fontSize: 11,
    textAlign: 'center',
  },
  seeAllButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 8,
    paddingVertical: 10,
    gap: 4,
  },
  seeAllText: {
    color: '#42A0FF',
    fontSize: 13,
    fontWeight: '600',
  },
});