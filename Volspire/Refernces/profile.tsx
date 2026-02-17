import React, { useRef, useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Animated,
  TouchableOpacity,
  Dimensions,
  Platform,
  StatusBar,
  Share,
  Alert,
} from 'react-native';
import { Image as ExpoImage } from 'expo-image';
import { LinearGradient } from 'expo-linear-gradient';
import { useAuth } from '@/context/AuthContext';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { LoadingScreen } from '@/components/LoadingScreen';
import { useAudio } from '@/context/AudioContext';
import { useAppDispatch, useAppSelector } from '@/store/hooks';
import { fetchUserProfile, fetchUserTracks, Track, checkIfFollowing, followUser, updateTrackVisibility, deleteTrack } from '@/store/slices/userProfileSlice';
import { OptimizedImage } from '@/components/OptimizedProfilePic';
import { ServicesSection } from '@/components/Profile/ServicesSection';
import { supabase } from '@/lib/supabase';

const HEADER_HEIGHT = 60;
const HERO_HEIGHT = 200;
const { width } = Dimensions.get('window');

interface ProfileViewProps {
  userId: string;
  isSelfView?: boolean;
}

export function ProfileView({ userId, isSelfView = false }: ProfileViewProps) {
  const scrollY = useRef(new Animated.Value(0)).current;
  const [activeTab, setActiveTab] = useState<'Services' | 'Tracks'>('Tracks');
  const { user } = useAuth();
  const router = useRouter();
  const { loadQueue } = useAudio();
  const dispatch = useAppDispatch();
  
  // Get data from Redux store
  const userProfile = useAppSelector((state) => 
    isSelfView ? state.userProfile.currentUserProfile : state.userProfile.profilesByUserId[userId]
  );
  const userTracks = useAppSelector((state) => state.userProfile.tracksByUserId[userId] || []);
  const profileLoading = useAppSelector((state) => state.userProfile.loading);
  const tracksLoading = useAppSelector((state) => state.userProfile.userTracksLoading);
  const [isFollowing, setIsFollowing] = useState(false);
  const [followLoading, setFollowLoading] = useState(false);
  const [isEditMode, setIsEditMode] = useState(false);
  const [deletingTrackId, setDeletingTrackId] = useState<string | null>(null);
  const [updatingVisibilityTrackId, setUpdatingVisibilityTrackId] = useState<string | null>(null);

  // Animated value for sliding the tab content horizontally
  const slideAnim = useRef(new Animated.Value(-width)).current;

  // Fetch user profile data
  useEffect(() => {
    if (userId) {
      dispatch(fetchUserProfile(userId));
      dispatch(fetchUserTracks(userId));
      
      // Check if following (only if not self view and user is logged in)
      if (!isSelfView && user?.id) {
        dispatch(checkIfFollowing(userId)).then((result) => {
          if (result.payload && typeof result.payload === 'object' && 'isFollowing' in result.payload) {
            setIsFollowing(result.payload.isFollowing as boolean);
          }
        });
      }
    }
  }, [userId, dispatch, isSelfView, user?.id]);

  const handleTrackPress = async (track: Track, trackIndex: number) => {
    try {
      // Transform tracks to match TrackPlayer interface
      const trackPlayerTracks = userTracks.map((t) => ({
        id: t.track_id,
        title: t.title,
        artist: t.users?.username || 'Unknown Artist',
        artwork: t.cover_url || '',
        url: t.audio_url || '', // Required by TrackPlayer
        cover_url: t.cover_url || '',
        audio_url: t.audio_url || '',
        visual_url: t.visual_url || '',
        track_id: t.track_id,
        profile_image_url: t.users?.profile_image_url || '',
        user_id: t.created_by,
        user_profile_pic: t.users?.profile_image_url || '',
      }));
      
      // Load the entire user tracks queue and start playing the selected track
      await loadQueue(trackPlayerTracks, trackIndex, true);
    } catch (error) {
      console.error('Error playing track:', error);
    }
  };

  const handleShareProfile = async () => {
    try {
      const profileUrl = `https://volspire.com/profile/${userId}`;
      const message = `Check out ${userProfile?.username}'s profile on Volspire! ${profileUrl}`;
      
      const result = await Share.share({
        message: message,
        url: profileUrl,
        title: `${userProfile?.username}'s Volspire Profile`,
      });

      if (result.action === Share.sharedAction) {
        console.log('Profile shared successfully');
      }
    } catch (error: any) {
      console.error('Error sharing profile:', error);
    }
  };

  const handleFollowPress = async () => {
    if (!user) {
      Alert.alert('Sign In Required', 'Please sign in to follow users');
      return;
    }

    setFollowLoading(true);
    try {
      const result = await dispatch(followUser(userId)).unwrap();
      setIsFollowing(result.isFollowing);
    } catch (error) {
      console.error('Error following user:', error);
      Alert.alert('Error', 'Failed to follow/unfollow user');
    } finally {
      setFollowLoading(false);
    }
  };

  const handleMessagePress = () => {
    router.push({
      pathname: '/pages/compose-message',
      params: {
        recipientUsername: userProfile?.username,
        recipientUserId: userId,
      },
    });
  };

  const handleDeleteTrack = async (trackId: string) => {
    Alert.alert(
      'Delete Track',
      'Are you sure you want to delete this track? This action cannot be undone.',
      [
        {
          text: 'Cancel',
          style: 'cancel',
        },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            setDeletingTrackId(trackId);
            try {
              // Optimistically update the UI
              dispatch(deleteTrack({ userId, trackId }));

              // Delete from database
              const { error } = await supabase
                .from('tracks')
                .delete()
                .eq('track_id', trackId);

              if (error) {
                // Revert on error by refetching
                dispatch(fetchUserTracks(userId));
                throw error;
              }
            } catch (error) {
              console.error('Error deleting track:', error);
              Alert.alert('Error', 'Failed to delete track');
            } finally {
              setDeletingTrackId(null);
            }
          },
        },
      ]
    );
  };

  const handleToggleVisibility = async (trackId: string, currentVisibility: string | null) => {
    setUpdatingVisibilityTrackId(trackId);
    try {
      const newVisibility = currentVisibility === 'public' ? 'private' : 'public';
      
      // Optimistically update the UI immediately
      dispatch(updateTrackVisibility({ userId, trackId, visibility: newVisibility }));

      // Update in database
      const { error } = await supabase
        .from('tracks')
        .update({ visibility: newVisibility })
        .eq('track_id', trackId);

      if (error) {
        // Revert on error by refetching
        dispatch(fetchUserTracks(userId));
        throw error;
      }
    } catch (error) {
      console.error('Error updating track visibility:', error);
      Alert.alert('Error', 'Failed to update track visibility');
    } finally {
      setUpdatingVisibilityTrackId(null);
    }
  };

  // Helper to format dates
  const formatDate = (dateString: string) => {
    if (!dateString) return '';
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return '';
    return date.toLocaleDateString('en-US', {
      month: 'long',
      day: 'numeric',
      year: 'numeric',
    });
  };

  // Helper to format relative time
  const formatRelativeTime = (dateString: string) => {
    if (!dateString) return '';
    const date = new Date(dateString);
    if (isNaN(date.getTime())) return '';
    
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffSeconds = Math.floor(diffMs / 1000);
    const diffMinutes = Math.floor(diffSeconds / 60);
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);
    const diffWeeks = Math.floor(diffDays / 7);
    const diffMonths = Math.floor(diffDays / 30);
    const diffYears = Math.floor(diffDays / 365);

    if (diffYears > 0) return `${diffYears} ${diffYears === 1 ? 'year' : 'years'} ago`;
    if (diffMonths > 0) return `${diffMonths} ${diffMonths === 1 ? 'month' : 'months'} ago`;
    if (diffWeeks > 0) return `${diffWeeks} ${diffWeeks === 1 ? 'week' : 'weeks'} ago`;
    if (diffDays > 0) return `${diffDays} ${diffDays === 1 ? 'day' : 'days'} ago`;
    if (diffHours > 0) return `${diffHours} ${diffHours === 1 ? 'hour' : 'hours'} ago`;
    if (diffMinutes > 0) return `${diffMinutes} ${diffMinutes === 1 ? 'minute' : 'minutes'} ago`;
    return 'Just now';
  };

  // Animate slide when activeTab changes
  useEffect(() => {
    Animated.spring(slideAnim, {
      toValue: activeTab === 'Services' ? 0 : -width,
      useNativeDriver: true,
      stiffness: 200,
      damping: 30,
      mass: 1,
    }).start();
  }, [activeTab, slideAnim]);

  if (profileLoading) {
    return <LoadingScreen />;
  }

  if (!userProfile) {
    return (
      <View style={[StyleSheet.absoluteFill, { backgroundColor: '#1a1a1a', justifyContent: 'center', alignItems: 'center' }]}>
        <Text style={{ color: 'white', fontSize: 16, textAlign: 'center', marginBottom: 20 }}>
          Profile not found.
        </Text>
      </View>
    );
  }

  const headerOpacity = scrollY.interpolate({
    inputRange: [HERO_HEIGHT - HEADER_HEIGHT, HERO_HEIGHT - HEADER_HEIGHT + 80],
    outputRange: [0, 1],
    extrapolate: 'clamp',
  });

  const headerTranslateY = scrollY.interpolate({
    inputRange: [0, HERO_HEIGHT - HEADER_HEIGHT],
    outputRange: [-HEADER_HEIGHT, 0],
    extrapolate: 'clamp',
  });

  return (
    <View style={{ flex: 1 }}>
      {/* Background Gradient */}
      <LinearGradient colors={['#1a1a1a', '#000']} style={StyleSheet.absoluteFill} />

      {/* Back Button (only for other users' profiles) */}
      {!isSelfView && (
        <TouchableOpacity 
          style={styles.backButton}
          onPress={() => router.back()}
          activeOpacity={0.7}
        >
          <Ionicons name="arrow-back" size={24} color="#fff" />
        </TouchableOpacity>
      )}

      {/* Sticky header */}
      <Animated.View
        style={[
          styles.header,
          {
            opacity: headerOpacity,
            transform: [{ translateY: headerTranslateY }],
          },
        ]}
      >
        <Text style={styles.headerTitle}>{userProfile?.username || 'Profile'}</Text>
      </Animated.View>

      <Animated.ScrollView
        scrollEventThrottle={16}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], {
          useNativeDriver: true,
        })}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {/* Hero */}
        <View style={styles.heroContainer}>
          {userProfile?.banner_image_url ? (
            <OptimizedImage
              uri={userProfile.banner_image_url}
              style={StyleSheet.absoluteFill}
            />
          ) : (
            <ExpoImage
              source={require('@/assets/images/test3.png')}
              style={StyleSheet.absoluteFill}
              contentFit="cover"
            />
          )}
          <View style={styles.overlay} />
        </View>

        {/* Profile Picture positioned halfway between hero and content */}
        <View style={styles.profileContainer}>
          <View style={styles.profilePicContainer}>
            {userProfile.profile_image_url ? (
              <OptimizedImage
                uri={userProfile.profile_image_url}
                style={styles.profileImage}
              />
            ) : (
              <View style={[styles.profileImage, styles.profileImagePlaceholder]}>
                <Ionicons name="person-sharp" size={64} color="#fff" />
              </View>
            )}
          </View>
          <View style={styles.profileInfoContainer}>
            <Text style={styles.name}>{userProfile?.username || 'User'}</Text>
          </View>
        </View>
        <Text style={styles.bio}>{userProfile?.bio?.trimEnd()}</Text>

        <View style={styles.infoRow}>
          {userProfile?.location && (
            <View style={styles.infoItem}>
              <Ionicons name="location-outline" size={16} color="#B8B8B8" />
              <Text style={styles.infoText}>{userProfile.location}</Text>
            </View>
          )}
          
          {userProfile?.occupation && (
            <View style={styles.infoItem}>
              <Ionicons name="briefcase-outline" size={16} color="#B8B8B8" />
              <Text style={styles.infoText}>{userProfile.occupation}</Text>
            </View>
          )}
        </View>
        
        {/* Stats Row: Followers & Monthly Listeners */}
        <View style={styles.statsRow}>
          <View style={styles.statItem}>
            <Text style={styles.statNumber}>{userProfile?.followers_count || 0}</Text>
            <Text style={styles.statLabel}>Followers</Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statNumber}>{userProfile?.monthly_listeners_count || 0}</Text>
            <Text style={styles.statLabel}>Monthly Listeners</Text>
          </View>
        </View>

        {/* Buttons */}
        {isSelfView && (userTracks.length >= 0) && (
          <View style={styles.metricsButtonContainer}>
            <TouchableOpacity 
              style={styles.metricsButton} 
              onPress={() => router.push('/pages/metrics')}
            >
              <Ionicons name="stats-chart" size={16} color="#fff" />
              <Text style={styles.metricsButtonText}>View Metrics</Text>
            </TouchableOpacity>
          </View>
        )}

        <View style={styles.buttonRow}>
          {isSelfView ? (
            <>
              <TouchableOpacity style={styles.editButton} onPress={() => router.push('/pages/edit-profile')}>
                <Text style={styles.editbuttonText}>Edit Profile</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.shareButton} onPress={handleShareProfile}>
                <Text style={styles.sharebuttonText}>Share Profile</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.settingsButton} onPress={() => router.push('/pages/settings')}>
                <Ionicons name="settings" size={16} color="#fff" />
              </TouchableOpacity>
            </>
          ) : (
            <>
              <TouchableOpacity 
                style={[styles.followButton, isFollowing && styles.followingButton]} 
                onPress={handleFollowPress}
                disabled={followLoading}
              >
                <Text style={[styles.followButtonText, isFollowing && styles.followingButtonText]}>
                  {followLoading ? 'Loading...' : isFollowing ? 'Following' : 'Follow'}
                </Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.messageButton} onPress={handleMessagePress}>
                <Text style={styles.messageButtonText}>Collab</Text>
              </TouchableOpacity>
                <TouchableOpacity style={styles.settingsButton}  onPress={handleShareProfile}>
                <Ionicons name="share" size={16} color="#fff" />
              </TouchableOpacity>
            </>
          )}
        </View>

        {/* Tabs */}
        <View style={styles.tabs}>
          <TouchableOpacity onPress={() => setActiveTab('Services')}>
            <Text style={[styles.tabItem, activeTab === 'Services' && styles.activeTab]}>
              Services
            </Text>
          </TouchableOpacity>
          <TouchableOpacity onPress={() => setActiveTab('Tracks')}>
            <Text style={[styles.tabItem, activeTab === 'Tracks' && styles.activeTab]}>
              Tracks
            </Text>
          </TouchableOpacity>
        </View>

        {/* Animated sliding container */}
        <Animated.View
          style={{
            flexDirection: 'row',
            width: width * 2,
            transform: [{ translateX: slideAnim }],
          }}
        >
          {/* Services Content */}
          <View style={{ width, marginBottom: 40 }}>
            <ServicesSection userId={userId} />
          </View>

          {/* Tracks Content */}
          <View style={{ width, marginBottom: 40 }}>
            {tracksLoading ? (
              <View style={styles.section}>
                <Text style={styles.loadingText}>Loading tracks...</Text>
              </View>
            ) : userTracks.length > 0 ? (
              <>
                <View style={styles.section}>
                  {(() => {
                    const publicTracks = userTracks.filter(track => track.visibility !== 'private');
                    const privateTracks = userTracks.filter(track => track.visibility === 'private');

                    return (
                      <>
                        {/* Public Tracks Section */}
                        {publicTracks.length > 0 && (
                          <>
                            {!isEditMode && (
                              <>
                                <View style={styles.sectionHeaderWithEdit}>
                                  <Text style={styles.sectionTitle}>Latest Release</Text>
                                  {isSelfView && user?.id === userId && (
                                    <TouchableOpacity 
                                      onPress={() => setIsEditMode(!isEditMode)} 
                                      style={styles.editButtonIcon}
                                    >
                                      <Ionicons 
                                        name="create-outline" 
                                        size={24} 
                                        color="#fff" 
                                      />
                                    </TouchableOpacity>
                                  )}
                                </View>
                                <TouchableOpacity 
                                  style={styles.trackCard}
                                  onPress={() => handleTrackPress(publicTracks[0], 0)}
                                  activeOpacity={0.7}
                                >
                                  <OptimizedImage
                                    uri={publicTracks[0].cover_url || undefined}
                                    style={styles.trackImage}
                                  />
                                  <View style={styles.trackContent}>
                                    <Text style={styles.trackTitle}>{publicTracks[0].title}</Text>
                                    <Text style={styles.trackArtist}>{publicTracks[0].users?.username || 'Solo Track'}</Text>
                                    <Text style={styles.trackDate}>{formatDate(publicTracks[0].created_at)}</Text>
                                  </View>
                                </TouchableOpacity>
                              </>
                            )}
                            
                            {isEditMode && (
                              <View style={styles.sectionHeaderWithEdit}>
                                <Text style={styles.sectionTitle}>Public Tracks</Text>
                                {isSelfView && user?.id === userId && (
                                  <TouchableOpacity 
                                    onPress={() => setIsEditMode(!isEditMode)} 
                                    style={styles.editButtonIcon}
                                  >
                                    <Ionicons 
                                      name="close-outline" 
                                      size={24} 
                                      color="#fff" 
                                    />
                                  </TouchableOpacity>
                                )}
                              </View>
                            )}

                            {!isEditMode && (
                              <Text style={[styles.sectionTitle, { marginTop: 20 }]}>
                                {isSelfView ? 'Public Tracks' : 'Tracks'}
                              </Text>
                            )}
                            {isEditMode ? (
                              <View>
                                {publicTracks.map((track, index) => (
                                  <View key={track.track_id} style={styles.trackListItem}>
                                    <OptimizedImage
                                      uri={track.cover_url || undefined}
                                      style={styles.trackListImage}
                                    />
                                    <View style={styles.trackListContent}>
                                      <Text style={styles.trackListTitle} numberOfLines={1}>{track.title}</Text>
                                      <Text style={styles.trackListArtist} numberOfLines={1}>
                                        {track.users?.username || 'Solo Track'}
                                      </Text>
                                      <Text style={styles.trackListPlays}>
                                        {track.streams || 0} plays • {formatRelativeTime(track.created_at)}
                                      </Text>
                                    </View>
                                    <View style={styles.trackListEditActions}>
                                      <TouchableOpacity
                                        onPress={() => handleToggleVisibility(track.track_id, track.visibility)}
                                        style={styles.trackListEditButton}
                                        disabled={updatingVisibilityTrackId === track.track_id}
                                      >
                                        <Ionicons 
                                          name={track.visibility === 'public' ? 'eye-off-outline' : 'eye-outline'} 
                                          size={22} 
                                          color="#42A0FF" 
                                        />
                                      </TouchableOpacity>
                                      <TouchableOpacity
                                        onPress={() => handleDeleteTrack(track.track_id)}
                                        style={styles.trackListEditButton}
                                        disabled={deletingTrackId === track.track_id}
                                      >
                                        <Ionicons name="trash-outline" size={22} color="#FF4444" />
                                      </TouchableOpacity>
                                    </View>
                                  </View>
                                ))}
                              </View>
                            ) : (
                              <View style={styles.trackGrid}>
                                {publicTracks.map((track, index) => (
                                  <TouchableOpacity 
                                    key={track.track_id}
                                    style={styles.trackGridItem}
                                    onPress={() => handleTrackPress(track, index)}
                                    activeOpacity={0.7}
                                  >
                                    <OptimizedImage
                                      uri={track.cover_url || undefined}
                                      style={styles.trackGridImage}
                                    />
                                    <Text style={styles.trackGridTitle} numberOfLines={2}>{track.title}</Text>
                                    <View style={styles.trackGridInfo}>
                                      <Text style={styles.trackGridPlays}>{track.streams || 0} plays</Text>
                                      <Text style={styles.trackGridDate}> • {formatRelativeTime(track.created_at)}</Text>
                                    </View>
                                  </TouchableOpacity>
                                ))}
                              </View>
                            )}
                          </>
                        )}

                        {/* Private Tracks Section */}
                        {privateTracks.length > 0 && isSelfView && user?.id === userId && (
                          <>
                            <Text style={[styles.sectionTitle, { marginTop: 20 }]}>Private Tracks</Text>
                            {isEditMode ? (
                              <View>
                                {privateTracks.map((track, index) => (
                                  <View key={track.track_id} style={styles.trackListItem}>
                                    <View style={styles.privateTrackBadgeContainer}>
                                      <OptimizedImage
                                        uri={track.cover_url || undefined}
                                        style={styles.trackListImage}
                                      />
                                      <View style={[styles.privateTrackBadge, { top: 4, right: 4 }]}>
                                        <Ionicons name="eye-off" size={10} color="#fff" />
                                      </View>
                                    </View>
                                    <View style={styles.trackListContent}>
                                      <Text style={styles.trackListTitle} numberOfLines={1}>{track.title}</Text>
                                      <Text style={styles.trackListArtist} numberOfLines={1}>
                                        {track.users?.username || 'Solo Track'}
                                      </Text>
                                      <Text style={styles.trackListPlays}>
                                        {track.streams || 0} plays • {formatRelativeTime(track.created_at)}
                                      </Text>
                                    </View>
                                    <View style={styles.trackListEditActions}>
                                      <TouchableOpacity
                                        onPress={() => handleToggleVisibility(track.track_id, track.visibility)}
                                        style={styles.trackListEditButton}
                                        disabled={updatingVisibilityTrackId === track.track_id}
                                      >
                                        <Ionicons 
                                          name="eye-outline" 
                                          size={22} 
                                          color="#42A0FF" 
                                        />
                                      </TouchableOpacity>
                                      <TouchableOpacity
                                        onPress={() => handleDeleteTrack(track.track_id)}
                                        style={styles.trackListEditButton}
                                        disabled={deletingTrackId === track.track_id}
                                      >
                                        <Ionicons name="trash-outline" size={22} color="#FF4444" />
                                      </TouchableOpacity>
                                    </View>
                                  </View>
                                ))}
                              </View>
                            ) : (
                              <View style={styles.trackGrid}>
                                {privateTracks.map((track, index) => (
                                  <TouchableOpacity 
                                    key={track.track_id}
                                    style={styles.trackGridItem}
                                    onPress={() => handleTrackPress(track, publicTracks.length + index)}
                                    activeOpacity={0.7}
                                  >
                                    <View style={styles.privateTrackBadgeContainer}>
                                      <OptimizedImage
                                        uri={track.cover_url || undefined}
                                        style={styles.trackGridImage}
                                      />
                                      <View style={styles.privateTrackBadge}>
                                        <Ionicons name="eye-off" size={12} color="#fff" />
                                      </View>
                                    </View>
                                    <Text style={styles.trackGridTitle} numberOfLines={2}>{track.title}</Text>
                                    <View style={styles.trackGridInfo}>
                                      <Text style={styles.trackGridPlays}>{track.streams || 0} plays</Text>
                                      <Text style={styles.trackGridDate}> • {formatRelativeTime(track.created_at)}</Text>
                                    </View>
                                  </TouchableOpacity>
                                ))}
                              </View>
                            )}
                          </>
                        )}
                      </>
                    );
                  })()}
                </View>
              </>
            ) : (
              <View style={styles.section}>
                <View style={styles.emptyStateContainer}>
                  <Ionicons name="musical-notes-outline" size={80} color="#555" />
                  <Text style={styles.emptyStateTitle}>No Tracks Yet</Text>
                  <Text style={styles.emptyStateDescription}>
                    {isSelfView ? 'Start sharing your music with the world today!' : 'This user hasn\'t posted any tracks yet.'}
                  </Text>
                </View>
              </View>
            )}
          </View>
        </Animated.View>
      </Animated.ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  backButton: {
    position: 'absolute',
    top: Platform.OS === 'android' ? (StatusBar.currentHeight || 24) + 16 : 60,
    left: 16,
    zIndex: 20,
    width: 40,
    height: 40,
    borderRadius: 20,
    // backgroundColor: 'rgba(0, 0, 0, 0.5)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  header: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    height: 60 + (Platform.OS === 'android' ? StatusBar.currentHeight || 24 : 44),
    backgroundColor: '#1a1a1a',
    justifyContent: 'flex-end',
    alignItems: 'center',
    paddingBottom: 10,
    zIndex: 10,
  },
  headerTitle: {
    color: 'white',
    fontSize: 18,
    fontWeight: 'bold',
  },
  heroContainer: {
    height: HERO_HEIGHT + (Platform.OS === 'android' ? StatusBar.currentHeight || 24 : 44),
    justifyContent: 'flex-end',
    paddingTop: Platform.OS === 'android' ? StatusBar.currentHeight || 24 : 44,
  },
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0, 0, 0, 0.17)',
  },
  profileContainer: {
    flexDirection: 'row',
  },
  profilePicContainer: {
    marginTop: -55,
    marginBottom: 10,
    marginLeft: 10,
  },
  profileImage: {
    width: 110,
    height: 110,
    borderRadius: 100,
  },
  profileImagePlaceholder: {
    backgroundColor: 'rgba(31, 31, 31, 1)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  profileInfoContainer: {
    paddingHorizontal: 4,
    alignItems: 'flex-start',
    paddingTop: 10,
    paddingLeft: 8,
  },
  name: {
    fontSize: 24,
    fontWeight: 'bold',
    color: 'white',
    textAlign: 'center',
  },
  statsRow: {
    flexDirection: 'row',
    paddingHorizontal: 8,
    paddingVertical: 10,
    gap: 20,
  },
  statItem: {
    display: 'flex',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-start',
    gap: 6,
  },
  statNumber: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  statLabel: {
    color: '#B8B8B8',
    fontSize: 13,
  },
  infoRow: {
    flexDirection: 'row',
    paddingHorizontal: 6,
    paddingVertical: 8,
    gap: 30,
  },
  infoItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  infoText: {
    color: '#B8B8B8',
    fontSize: 13,
  },
  bio: {
    color: '#ffffffff',
    paddingHorizontal: 8,
    paddingVertical: 4,
    fontSize: 13,
  },
  metricsButtonContainer: {
    paddingHorizontal: 8,
    paddingTop: 8,
    paddingBottom: 4,
  },
  metricsButton: {
    backgroundColor: 'rgba(131, 131, 131, 0.15)',
    paddingVertical: 10,
    paddingHorizontal: 16,
    borderRadius: 8,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  metricsButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 14,
    alignItems: 'center',
    paddingVertical: 19
  },
  editButton: {
    borderWidth: 1,
    backgroundColor: '#3B82F6',
    paddingVertical: 10,
    width: '40%',
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 5,
  },
  shareButton: {
    paddingVertical: 10,
    paddingHorizontal: 20,
    alignItems: 'center',
    backgroundColor: 'white',
    justifyContent: 'center',
    borderRadius: 5,
    borderWidth: 1,
    borderColor: 'white',
    width: '40%',
    flexDirection: 'row',
    gap: 8,
  },
  settingsButton: {
    borderWidth: 1,
    // backgroundColor: 'white',
    borderColor: 'white',
    paddingVertical: 8,
    paddingHorizontal: 8,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 5,
  },
  followButton: {
    backgroundColor: '#0073E8',
    paddingVertical: 10,
    paddingHorizontal: 30,
    width: '40%',
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 5,
  },
  followingButton: {
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: '#fff',
  },
  followButtonText: {
    color: '#fff',
    fontWeight: '500',
    fontSize: 13,
  },
  followingButtonText: {
    color: '#fff',
  },
  messageButton: {
    borderWidth: 1,
    borderColor: 'white',
    backgroundColor: 'white',
    paddingVertical: 10,
    paddingHorizontal: 20,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 5,
    flexDirection: 'row',
    gap: 8,
    width: '40%',
  },
  messageButtonText: {
    color: '#000000ff',
    fontWeight: '500',
    fontSize: 13,
  },
  editbuttonText: {
    color: '#ffffffff',
    fontWeight: '500',
    fontSize: 13,
  },
  sharebuttonText: {
    color: '#000000ff',
    fontWeight: '500',
    fontSize: 13,
  },
  tabs: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: 30,
    paddingVertical: 20,
  },
  tabItem: {
    color: '#aaa',
    fontSize: 15,
    paddingHorizontal: 10,
    paddingBottom: 4,
  },
  activeTab: {
    color: 'white',
    fontWeight: 'bold',
    borderBottomWidth: 2,
    borderBottomColor: '#ffffffff',
  },
  section: {
    marginTop: 12,
    paddingHorizontal: 4,
    marginBottom: 12,
  },
  sectionTitle: {
    color: 'white',
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 12,
  },
  trackCard: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderRadius: 12,
    marginBottom: 16,
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
  },
  trackImage: {
    width: 60,
    height: 60,
    borderRadius: 8,
    marginRight: 12,
  },
  trackContent: {
    flex: 1,
  },
  trackTitle: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 2,
  },
  trackArtist: {
    color: '#B8B8B8',
    fontSize: 14,
    marginBottom: 4,
  },
  trackDate: {
    color: '#888',
    fontSize: 12,
  },
  trackGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-start',
    gap: 12,
  },
  trackGridItem: {
    width: (width - 64) / 3,
    marginBottom: 16,
  },
  trackGridImage: {
    width: '100%',
    aspectRatio: 1,
    borderRadius: 8,
    marginBottom: 8,
  },
  trackGridTitle: {
    color: 'white',
    fontSize: 14,
    fontWeight: '600',
    marginBottom: 4,
    lineHeight: 16,
  },
  trackGridInfo: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  trackGridPlays: {
    color: '#B8B8B8',
    fontSize: 10,
  },
  trackGridDate: {
    color: '#888',
    fontSize: 10,
  },
  loadingText: {
    color: '#888',
    fontSize: 14,
    textAlign: 'center',
    marginVertical: 40,
  },
  emptyStateContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 60,
    paddingHorizontal: 20,
  },
  emptyStateTitle: {
    color: 'white',
    fontSize: 24,
    fontWeight: '600',
    marginTop: 20,
    marginBottom: 12,
  },
  emptyStateDescription: {
    color: '#B8B8B8',
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 24,
    lineHeight: 22,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 20,
    paddingHorizontal: 8,
  },
  sectionHeaderWithEdit: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 12,
    paddingHorizontal: 0,
  },
  editButtonIcon: {
    paddingRight: 26,
  },
  trackEditActions: {
    flexDirection: 'row',
    gap: 12,
    marginLeft: 12,
  },
  trackEditButton: {
    padding: 8,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 8,
  },
  trackGridEditActions: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 8,
    justifyContent: 'center',
  },
  trackGridEditButton: {
    padding: 6,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 6,
    flex: 1,
    alignItems: 'center',
  },
  privateTrackBadgeContainer: {
    position: 'relative',
  },
  privateTrackBadge: {
    position: 'absolute',
    top: 6,
    right: 6,
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    borderRadius: 12,
    padding: 4,
  },
  trackListItem: {
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    borderRadius: 12,
    marginBottom: 12,
    padding: 12,
    flexDirection: 'row',
    alignItems: 'center',
  },
  trackListImage: {
    width: 60,
    height: 60,
    borderRadius: 8,
    marginRight: 12,
  },
  trackListContent: {
    flex: 1,
    marginRight: 8,
  },
  trackListTitle: {
    color: 'white',
    fontSize: 15,
    fontWeight: '600',
    marginBottom: 3,
  },
  trackListArtist: {
    color: '#B8B8B8',
    fontSize: 13,
    marginBottom: 3,
  },
  trackListPlays: {
    color: '#888',
    fontSize: 11,
  },
  trackListEditActions: {
    flexDirection: 'row',
    gap: 8,
  },
  trackListEditButton: {
    padding: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    borderRadius: 8,
  },
});
