import React from 'react';
import {
  ActivityIndicator,
  Image,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  TextInput,
  View,
  useColorScheme,
} from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { Link, useLocalSearchParams } from 'expo-router';
import { useTranslation } from 'react-i18next';

const NAVY = '#0F1C3F';
const GOLD = '#D4A843';

import { PlaceImage } from '@/components/place-image';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import {
  type AIConversationMessage,
  type AIRecommendation,
  fetchRecommendations,
} from '@/src/api/places';
import { useUserProfile } from '@/src/store/user-profile';
import { useWeather, weatherEmoji } from '@/src/hooks/use-weather';
import { useCityStore } from '@/src/store/city';
import { CATEGORY_EMOJI, formatCategory } from '@/src/utils/categories';
import { getCurrentLocation } from '@/src/utils/location';

type AttachedImage = { uri: string; base64: string };

type ConversationTurn =
  | {
      id: string;
      role: 'user';
      content: string;
      imageUri?: string;
    }
  | {
      id: string;
      role: 'assistant';
      content: string;
      recommendations: AIRecommendation[];
    };

export default function AiScreen() {
  const colorScheme = useColorScheme();
  const dark = colorScheme === 'dark';
  const { t, i18n } = useTranslation();
  const params = useLocalSearchParams<{ q?: string }>();
  const scrollRef = React.useRef<ScrollView>(null);
  const inputRef = React.useRef<TextInput>(null);
  const [query, setQuery] = React.useState(params.q ?? '');
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [conversation, setConversation] = React.useState<ConversationTurn[]>([]);
  const [attachedImage, setAttachedImage] = React.useState<AttachedImage | null>(null);

  const autoSubmittedRef = React.useRef(false);
  const locationRef = React.useRef<{ lat: number; lng: number } | null | undefined>(undefined);
  const { name, profession, interests, faith } = useUserProfile();
  const userProfile = { name, profession, interests, faith };
  const { weather } = useWeather();
  const { cityName } = useCityStore();

  const suggestions = React.useMemo(() => {
    const base = [
      t('ai.suggestions.bestCafes'),
      t('ai.suggestions.uniqueLocal'),
      t('ai.suggestions.soloAfternoon'),
      t('ai.suggestions.bestView'),
    ];
    if (weather?.condition === 'rainy' || weather?.condition === 'stormy') {
      return [t('ai.suggestions.cozyRainy'), ...base.slice(0, 3)];
    }
    if (weather?.condition === 'sunny' && (weather?.temp ?? 0) > 18) {
      return [t('ai.suggestions.outdoorTerraces'), ...base.slice(0, 3)];
    }
    if (profession === 'photographer') return [t('ai.suggestions.photoSpots'), ...base.slice(0, 3)];
    if (profession === 'architect') return [t('ai.suggestions.architectureBuildings'), ...base.slice(0, 3)];
    if (profession === 'foodie') return [t('ai.suggestions.localFood'), ...base.slice(0, 3)];
    return base;
  }, [weather?.condition, weather?.temp, profession, t]);

  const history = React.useMemo<AIConversationMessage[]>(
    () =>
      conversation.map((turn) => ({
        role: turn.role,
        content: turn.content,
      })),
    [conversation]
  );

  const handleAttachImage = React.useCallback(async (fromCamera: boolean) => {
    const picker = fromCamera ? ImagePicker.launchCameraAsync : ImagePicker.launchImageLibraryAsync;
    const result = await picker({ mediaTypes: ['images'], base64: true, quality: 0.6 });
    if (!result.canceled && result.assets[0]?.base64) {
      setAttachedImage({ uri: result.assets[0].uri, base64: result.assets[0].base64 });
    }
  }, []);

  const handleRemoveImage = React.useCallback(() => setAttachedImage(null), []);

  const handleSearch = React.useCallback(async (overrideQuery?: string) => {
    const nextQuery = (overrideQuery ?? query).trim();
    if (!nextQuery) return;

    const nextImage = overrideQuery ? null : attachedImage;

    setLoading(true);
    setError(null);
    setQuery('');
    setAttachedImage(null);

    const userTurn: ConversationTurn = {
      id: `${Date.now()}-user`,
      role: 'user',
      content: nextQuery,
      imageUri: nextImage?.uri,
    };

    setConversation((current) => [...current, userTurn]);

    try {
      if (locationRef.current === undefined) {
        locationRef.current = (await getCurrentLocation()) ?? null;
      }

      const data = await fetchRecommendations(
        nextQuery,
        history,
        userProfile,
        weather ?? undefined,
        cityName,
        locationRef.current ?? undefined,
        nextImage ? { base64: nextImage.base64, mimeType: 'image/jpeg' } : undefined,
        i18n.language
      );
      const assistantTurn: ConversationTurn = {
        id: `${Date.now()}-assistant`,
        role: 'assistant',
        content: data.answer,
        recommendations: data.recommendations,
      };

      setConversation((current) => [...current, assistantTurn]);
    } catch (err: unknown) {
      setQuery(nextQuery);

      if (
        err instanceof Error &&
        (err.message.includes('OPENROUTER_API_KEY') ||
          err.message.includes('OPENAI_API_KEY') ||
          err.message.includes('not configured in the backend'))
      ) {
        setError(t('ai.errorNotConfigured'));
      } else if (err instanceof Error) {
        setError(err.message);
      } else {
        setError(t('ai.errorGeneric'));
      }
    } finally {
      setLoading(false);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, history, userProfile, weather, cityName, attachedImage, t, i18n.language]);

  // Auto-submit once if navigated from scan with a pre-filled query
  React.useEffect(() => {
    if (params.q && !autoSubmittedRef.current) {
      autoSubmittedRef.current = true;
      const t = setTimeout(() => handleSearch(), 300);
      return () => clearTimeout(t);
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const bgColor = dark ? '#0A0F1E' : '#F4F5F9';
  const inputBg = dark ? '#1A2340' : '#fff';
  const inputColor = dark ? '#fff' : '#000';

  return (
    <ThemedView style={[styles.container, { backgroundColor: bgColor }]}>
      {/* Navy header */}
      <SafeAreaView style={{ backgroundColor: NAVY }}>
        <View style={styles.header}>
          <View style={{ flex: 1 }}>
            <ThemedText style={styles.headerTitle} lightColor={GOLD} darkColor={GOLD}>
              {t('ai.title')}
            </ThemedText>
            <ThemedText style={styles.headerSub} lightColor="rgba(255,255,255,0.65)" darkColor="rgba(255,255,255,0.65)">
              {weather
                ? t('ai.headerSub.withWeather', { emoji: weatherEmoji(weather.condition), temp: weather.temp, city: cityName ?? t('common.everywhere') })
                : cityName ?? t('ai.headerSub.fallback')}
            </ThemedText>
          </View>
          {conversation.length > 0 && (
            <Pressable
              onPress={() => { setConversation([]); setError(null); }}
              style={({ pressed }) => [styles.clearBtn, pressed && { opacity: 0.6 }]}>
              <ThemedText style={styles.clearBtnText} lightColor="rgba(255,255,255,0.55)" darkColor="rgba(255,255,255,0.55)">
                {t('common.clear')}
              </ThemedText>
            </Pressable>
          )}
        </View>
      </SafeAreaView>

      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.keyboardView}
        keyboardVerticalOffset={0}>

        {/* Conversation scroll area */}
        <ScrollView
          ref={scrollRef}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          onContentSizeChange={() => {
            scrollRef.current?.scrollToEnd({ animated: true });
          }}>

          {error && (
            <View style={styles.errorBox}>
              <ThemedText style={styles.errorText}>{error}</ThemedText>
            </View>
          )}

          {conversation.length === 0 ? (
            <View style={styles.emptyBox}>
              <ThemedText style={styles.emptyHint}>{t('ai.tryAsking')}</ThemedText>
              <View style={styles.suggestionGrid}>
                {suggestions.map((s) => (
                  <Pressable
                    key={s}
                    style={({ pressed }) => [styles.suggestionChip, pressed && { opacity: 0.7 }]}
                    onPress={() => handleSearch(s)}>
                    <ThemedText style={styles.suggestionText}>{s}</ThemedText>
                  </Pressable>
                ))}
              </View>
            </View>
          ) : (
            <View style={styles.conversation}>
              {conversation.map((turn) =>
                turn.role === 'user' ? (
                  <View key={turn.id} style={[styles.messageBubble, styles.userBubble]}>
                    {turn.imageUri ? (
                      <Image source={{ uri: turn.imageUri }} style={styles.userImage} />
                    ) : null}
                    <ThemedText style={styles.userText}>{turn.content}</ThemedText>
                  </View>
                ) : (
                  <View key={turn.id} style={styles.assistantBlock}>
                    <View style={[styles.messageBubble, styles.assistantBubble]}>
                      <ThemedText style={styles.assistantText}>{turn.content}</ThemedText>
                    </View>

                    {turn.recommendations.length > 0 ? (
                      <View style={styles.resultList}>
                        {turn.recommendations.map((place) => (
                          <Link
                            href={{ pathname: '/place/[id]', params: { id: place.id } }}
                            key={`${turn.id}-${place.id}`}
                            asChild>
                            <Pressable style={({ pressed }) => [styles.card, pressed && styles.pressed]}>
                              <PlaceImage place={place} style={styles.cardCover} />
                              <View style={styles.cardContent}>
                                <ThemedText style={styles.cardTitle}>{place.name}</ThemedText>
                                <ThemedText style={styles.cardTags}>
                                  {CATEGORY_EMOJI[place.category] ?? '📍'} {formatCategory(place.category, t)}
                                  {place.tags[0] ? ` · ${place.tags[0]}` : ''}
                                </ThemedText>
                                <View style={styles.reasonBox}>
                                  <ThemedText style={styles.sparkle}>✨</ThemedText>
                                  <ThemedText style={styles.reasonText}>{place.aiReason}</ThemedText>
                                </View>
                              </View>
                            </Pressable>
                          </Link>
                        ))}
                      </View>
                    ) : (
                      <View style={styles.emptyBoxInline}>
                        <ThemedText style={styles.emptyText}>{t('ai.noMatches')}</ThemedText>
                      </View>
                    )}
                  </View>
                )
              )}

              {/* Typing indicator */}
              {loading && (
                <View style={[styles.messageBubble, styles.assistantBubble, styles.typingBubble]}>
                  <ActivityIndicator size="small" color={GOLD} />
                </View>
              )}
            </View>
          )}
        </ScrollView>

        {/* Pinned input bar */}
        <SafeAreaView style={[styles.inputBar, { backgroundColor: bgColor }]}>
          {attachedImage ? (
            <View style={styles.attachedPreviewRow}>
              <Image source={{ uri: attachedImage.uri }} style={styles.attachedPreviewImage} />
              <Pressable
                onPress={handleRemoveImage}
                accessibilityLabel={t('ai.removePhoto')}
                style={({ pressed }) => [styles.attachedPreviewRemove, pressed && { opacity: 0.7 }]}>
                <ThemedText style={styles.attachedPreviewRemoveText}>×</ThemedText>
              </Pressable>
            </View>
          ) : null}
          <View style={styles.inputRow}>
            <Pressable
              onPress={() => handleAttachImage(false)}
              disabled={loading}
              accessibilityLabel={t('ai.attachPhoto')}
              style={({ pressed }) => [styles.attachBtn, pressed && { opacity: 0.7 }, loading && styles.disabled]}>
              <ThemedText style={styles.attachBtnText}>📷</ThemedText>
            </Pressable>
            <TextInput
              ref={inputRef}
              style={[styles.input, { color: inputColor, backgroundColor: inputBg }]}
              placeholder={t('ai.inputPlaceholder')}
              placeholderTextColor={dark ? 'rgba(255,255,255,0.4)' : '#999'}
              value={query}
              onChangeText={setQuery}
              onSubmitEditing={() => handleSearch()}
              returnKeyType="send"
              editable={!loading}
            />
            <Pressable
              onPress={() => handleSearch()}
              disabled={loading || !query.trim()}
              style={({ pressed }) => [
                styles.button,
                pressed && styles.pressed,
                (loading || !query.trim()) && styles.disabled,
              ]}>
              <ThemedText style={styles.buttonText} lightColor="#fff" darkColor="#fff">{t('ai.ask')}</ThemedText>
            </Pressable>
          </View>
        </SafeAreaView>
      </KeyboardAvoidingView>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 16,
  },
  headerTitle: {
    fontSize: 26,
    fontWeight: '800',
    letterSpacing: 1,
  },
  headerSub: {
    fontSize: 14,
    marginTop: 4,
    lineHeight: 20,
  },
  clearBtn: {
    paddingHorizontal: 4,
    paddingVertical: 6,
  },
  clearBtnText: {
    fontSize: 15,
  },
  keyboardView: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
    paddingTop: 20,
    paddingBottom: 16,
    flexGrow: 1,
  },
  inputBar: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: 'rgba(127,127,127,0.2)',
  },
  inputRow: {
    flexDirection: 'row',
    gap: 8,
    paddingHorizontal: 16,
    paddingVertical: 10,
  },
  input: {
    flex: 1,
    height: 48,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.3)',
    borderRadius: 24,
    paddingHorizontal: 16,
    fontSize: 16,
  },
  attachBtn: {
    width: 48,
    height: 48,
    borderRadius: 24,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.3)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  attachBtnText: {
    fontSize: 18,
  },
  attachedPreviewRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 10,
    gap: 8,
  },
  attachedPreviewImage: {
    width: 44,
    height: 44,
    borderRadius: 10,
  },
  attachedPreviewRemove: {
    width: 24,
    height: 24,
    borderRadius: 12,
    backgroundColor: 'rgba(127,127,127,0.2)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  attachedPreviewRemoveText: {
    fontSize: 16,
    lineHeight: 18,
  },
  button: {
    height: 48,
    paddingHorizontal: 20,
    backgroundColor: NAVY,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
  },
  buttonText: {
    fontWeight: '600',
    fontSize: 16,
  },
  disabled: {
    opacity: 0.5,
  },
  pressed: {
    opacity: 0.8,
  },
  errorBox: {
    padding: 16,
    backgroundColor: '#FEF3F2',
    borderRadius: 12,
    marginBottom: 24,
  },
  errorText: {
    color: '#B42318',
  },
  conversation: {
    gap: 18,
  },
  assistantBlock: {
    gap: 12,
  },
  resultList: {
    gap: 16,
  },
  messageBubble: {
    borderRadius: 18,
    paddingHorizontal: 14,
    paddingVertical: 12,
  },
  userBubble: {
    alignSelf: 'flex-end',
    backgroundColor: NAVY,
    maxWidth: '88%',
  },
  assistantBubble: {
    backgroundColor: 'rgba(127,127,127,0.12)',
  },
  typingBubble: {
    alignSelf: 'flex-start',
    paddingHorizontal: 18,
  },
  userImage: {
    width: '100%',
    height: 140,
    borderRadius: 12,
    marginBottom: 8,
  },
  userText: {
    color: '#fff',
    fontSize: 15,
    lineHeight: 22,
  },
  assistantText: {
    fontSize: 15,
    lineHeight: 22,
  },
  card: {
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.2)',
    borderRadius: 16,
    overflow: 'hidden',
    backgroundColor: 'rgba(255,255,255,0.02)',
  },
  cardCover: {
    width: '100%',
    height: 140,
  },
  cardContent: {
    padding: 16,
    gap: 6,
  },
  cardTitle: {
    fontSize: 18,
    fontWeight: 'bold',
  },
  cardTags: {
    fontSize: 14,
    opacity: 0.6,
  },
  reasonBox: {
    flexDirection: 'row',
    backgroundColor: 'rgba(212,168,67,0.1)',
    borderWidth: 1,
    borderColor: 'rgba(212,168,67,0.25)',
    padding: 12,
    borderRadius: 12,
    marginTop: 8,
    gap: 8,
  },
  sparkle: {
    fontSize: 16,
  },
  reasonText: {
    flex: 1,
    color: '#9B7A1A',
    fontSize: 14,
    lineHeight: 20,
    fontWeight: '500',
  },
  emptyBox: {
    paddingVertical: 24,
    gap: 16,
  },
  emptyHint: {
    fontSize: 13,
    fontWeight: '600',
    opacity: 0.5,
    textTransform: 'uppercase',
    letterSpacing: 0.8,
  },
  suggestionGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
  },
  suggestionChip: {
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(15,28,63,0.15)',
    backgroundColor: 'rgba(15,28,63,0.05)',
  },
  suggestionText: {
    fontSize: 14,
    lineHeight: 20,
    fontWeight: '500',
  },
  emptyBoxInline: {
    paddingHorizontal: 4,
  },
  emptyText: {
    opacity: 0.65,
    textAlign: 'center',
    lineHeight: 22,
  },
});
