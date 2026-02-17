import React, { useCallback, useRef, useState, useEffect } from 'react';
import { StyleSheet, SafeAreaView, Pressable, View, Animated, Text } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { PlaybackControls } from './PlaybackControls';
import { ScrollingText } from '../Util/ScrollingText';
import { OptimizedProfilePic } from '../OptimizedProfilePic';
import { goBack } from 'expo-router/build/global-state/routing';
import { useAudio } from '@/context/AudioContext';
import { useAuth } from '@/context/AuthContext';
import { router } from 'expo-router';
import { SlidingCommentsPanel } from './SlidingCommentsPanel';
import { StaticTrackDisplay } from '../MusicPlayer/StaticTrackDisplay';
import { PlayerSideButtons } from '../PlayerSideButtons';
import { VideoView } from 'expo-video';

export default function ExpandedPlayer() {
    const {
        currentTrack,
        isPlaying,
        player,
        trackMetadata, // Get trackMetadata directly from AudioContext
    } = useAudio();
    const { user } = useAuth();

        const [showComments, setShowComments] = useState(false);
        const slideAnimation = useRef(new Animated.Value(0)).current;
        const previousTrackId = useRef(currentTrack?.id);

        // Close comments when track changes
        useEffect(() => {
            if (currentTrack?.id && previousTrackId.current !== currentTrack.id) {
                if (showComments) {
                    handleCloseComments();
                }
                previousTrackId.current = currentTrack.id;
            }
        }, [currentTrack?.id, showComments]);
    
        const handleToggleComments = useCallback(() => {
            const toValue = showComments ? 0 : 1;
            setShowComments(!showComments);
            Animated.timing(slideAnimation, {
                toValue,
                duration: 300,
                useNativeDriver: true,
            }).start();
        }, [showComments]);
    
        const handleCloseComments = useCallback(() => {
            setShowComments(false);
            Animated.timing(slideAnimation, {
                toValue: 0,
                duration: 300,
                useNativeDriver: true,
            }).start();
        }, [slideAnimation]);

        
    
  return (
    <SafeAreaView style={styles.container}>
        <LinearGradient
        colors={['#1a1a1a', '#000']}
        style={StyleSheet.absoluteFill}
        />
     
      
                <View style={{ flex: 1 }}>
                    <View style={{ flex: 1, overflow: 'hidden' }}>
                    <SlidingCommentsPanel
                        currentTrackId={currentTrack?.id}
                        showComments={showComments}
                        slideAnimation={slideAnimation}
                        onClose={handleCloseComments}
                    >
                                <View style={styles.container}> 
                                        <View style={styles.videoContainer}>
                                            {currentTrack?.visual_url ? (
                                                    <VideoView
                                                        player={player}
                                                        style={styles.video}
                                                        nativeControls={false}
                                                        contentFit="contain"
                                                        allowsPictureInPicture={false}
                                                    />
                                                ) : (
                                                    <View style={styles.placeholderContainer}>
                                                        <OptimizedProfilePic
                                                            uri={currentTrack?.artwork}
                                                            style={styles.albumCover}
                                                        />
                                                    </View>
                                                )}
                                        </View>       
                                        <View style={styles.buttonsRow}>
                                            <PlayerSideButtons 
                                                trackId={currentTrack?.id}
                                                commentsCount={currentTrack?.comments || 0}
                                                savesCount={currentTrack?.saves || 0}
                                                likesCount={currentTrack?.likes || 0}
                                                onCommentPress={handleToggleComments}
                                                horizontal
                                            />
                                        </View>
                                        <View style={styles.carouselRow}>
                                            <StaticTrackDisplay 
                                                trackMetadata={trackMetadata || {
                                                    id: currentTrack?.id || '',
                                                    title: currentTrack?.title || '',
                                                    artist: currentTrack?.artist || '',
                                                    artwork: currentTrack?.artwork,
                                                }}
                                                isPlaying={isPlaying}
                                            />                                        
                                        </View>
                                    <View style={styles.titleContainer}>
                                        <View style={styles.titleLeft}>
                                            {/* Profile pic */}
                                            <Pressable onPress={() => {
                                                    if (currentTrack?.user_id) {
                                                        // Check if it's the user's own profile
                                                        if (user?.id && currentTrack.user_id === user.id) {
                                                            router.push('/(tabs)/profile');
                                                        } else {
                                                            // Navigate to other user's profile
                                                            router.push(`/user/${currentTrack.user_id}`);
                                                        }
                                                    }
                                                }} style={styles.listeningProfileContainer}>
                                                    <OptimizedProfilePic
                                                        uri={currentTrack?.user_profile_pic || currentTrack?.artwork}
                                                        style={styles.listeningProfilePic}
                                                    />
                                                </Pressable>
                                            <View style={styles.titleTextContainer}>
                                                <ScrollingText 
                                                    title={currentTrack?.title || ''} 
                                                    artist={''}
                                                    fontSize={16}
                                                />                            
                                                <Text style={styles.artist}>{currentTrack?.artist}</Text>
                                            </View>
                                        </View>
                                    </View>
                                </View>
                    </SlidingCommentsPanel>
                </View>
       {/* Controls */}
      <PlaybackControls />
      </View>
      
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { 
    flex: 1,
    justifyContent: 'flex-end'
  },
  videoContainer: {
    flex: 1,
    width: '100%',
  },
  video: {
    width: '100%',
    height: '100%',
  },
  placeholderContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  albumCover: {
    width: 300,
    height: 300,
    borderRadius: 8,
  },
  titleContainer: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    width: '100%',
    paddingVertical: 10,
    paddingHorizontal: 18,
},
titleLeft: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
},
titleTextContainer: {
    flex: 1,
},
listeningProfileContainer: {
    marginRight: 0,
},
listeningProfilePic: {
    width: 44,
    height: 44,
    borderRadius: 25,
},
    artist: {
        color: '#fff',
        fontSize: 16,
        opacity: 0.8,
        marginBottom: 8,
    },
    buttonsRow: {
        width: '100%',
        paddingHorizontal: 6,
        paddingVertical: 8,
        alignItems: 'flex-start',
        marginBottom: 6,
        justifyContent: 'flex-end',
    },
    carouselContainer: {
        flex: 1,
    },
    carouselRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 20,
    },
    narrowCarouselContainer: {
        flex: 1,
    },
});