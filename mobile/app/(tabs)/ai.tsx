import React from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  TextInput,
  View,
} from 'react-native';
import { Link } from 'expo-router';

import { PlaceImage } from '@/components/place-image';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import {
  type AIConversationMessage,
  type AIRecommendation,
  fetchRecommendations,
} from '@/src/api/places';

type ConversationTurn =
  | {
      id: string;
      role: 'user';
      content: string;
    }
  | {
      id: string;
      role: 'assistant';
      content: string;
      recommendations: AIRecommendation[];
    };

export default function AiScreen() {
  const scrollRef = React.useRef<ScrollView>(null);
  const [query, setQuery] = React.useState('');
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [conversation, setConversation] = React.useState<ConversationTurn[]>([]);

  const history = React.useMemo<AIConversationMessage[]>(
    () =>
      conversation.map((turn) => ({
        role: turn.role,
        content: turn.content,
      })),
    [conversation]
  );

  const handleSearch = async () => {
    const nextQuery = query.trim();
    if (!nextQuery) return;

    setLoading(true);
    setError(null);
    setQuery('');

    const userTurn: ConversationTurn = {
      id: `${Date.now()}-user`,
      role: 'user',
      content: nextQuery,
    };

    setConversation((current) => [...current, userTurn]);

    try {
      const data = await fetchRecommendations(nextQuery, history);
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
        setError('AI recommendations are not configured in the backend yet.');
      } else if (err instanceof Error) {
        setError(err.message);
      } else {
        setError('Error fetching recommendations.');
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <ThemedView style={styles.container}>
      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.keyboardView}
        keyboardVerticalOffset={90}>
        <ScrollView
          ref={scrollRef}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
          onContentSizeChange={() => {
            scrollRef.current?.scrollToEnd({ animated: true });
          }}>
          <View style={styles.header}>
            <ThemedText type="title">Ask AI</ThemedText>
            <ThemedText style={styles.subtitle}>
              Describe what you feel like doing, who you are with, or your vibe today.
            </ThemedText>
            <ThemedText style={styles.note}>
              AI recommendations only surface the strongest, higher-confidence options. Use the Map tab for open-ended exploration of any location.
            </ThemedText>
            <ThemedText style={styles.note}>
              Ask follow-up questions naturally. The recent conversation is now sent back to the backend each turn.
            </ThemedText>
          </View>

          {error && (
            <View style={styles.errorBox}>
              <ThemedText style={styles.errorText}>{error}</ThemedText>
            </View>
          )}

          {conversation.length === 0 ? (
            <View style={styles.emptyBox}>
              <ThemedText style={styles.emptyText}>
                Try a natural prompt like “I am in a museum now, where should I go next?”
              </ThemedText>
            </View>
          ) : (
            <View style={styles.conversation}>
              {conversation.map((turn) =>
                turn.role === 'user' ? (
                  <View key={turn.id} style={[styles.messageBubble, styles.userBubble]}>
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
                                  {place.tags.slice(0, 3).join(' · ')}
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
                        <ThemedText style={styles.emptyText}>
                          No matches this turn. Try a broader follow-up.
                        </ThemedText>
                      </View>
                    )}
                  </View>
                )
              )}
            </View>
          )}

          <View style={styles.searchContainer}>
            <TextInput
              style={styles.input}
              placeholder="e.g. I am in a museum now, where next?"
              placeholderTextColor="#999"
              value={query}
              onChangeText={setQuery}
              onSubmitEditing={handleSearch}
              returnKeyType="send"
            />
            <Pressable
              onPress={handleSearch}
              disabled={loading || !query.trim()}
              style={({ pressed }) => [
                styles.button,
                pressed && styles.pressed,
                (loading || !query.trim()) && styles.disabled,
              ]}>
              {loading ? (
                <ActivityIndicator color="#fff" />
              ) : (
                <ThemedText style={styles.buttonText}>Ask</ThemedText>
              )}
            </Pressable>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  keyboardView: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
    paddingTop: 60,
    paddingBottom: 40,
  },
  header: {
    marginBottom: 24,
  },
  subtitle: {
    marginTop: 8,
    opacity: 0.7,
    fontSize: 16,
    lineHeight: 22,
  },
  note: {
    marginTop: 10,
    fontSize: 14,
    lineHeight: 20,
    opacity: 0.78,
  },
  searchContainer: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 20,
  },
  input: {
    flex: 1,
    height: 48,
    borderWidth: 1,
    borderColor: 'rgba(127,127,127,0.3)',
    borderRadius: 24,
    paddingHorizontal: 16,
    fontSize: 16,
    color: '#000',
    backgroundColor: '#fff',
  },
  button: {
    height: 48,
    paddingHorizontal: 20,
    backgroundColor: '#000',
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
  },
  buttonText: {
    color: '#fff',
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
    backgroundColor: '#0D5A50',
    maxWidth: '88%',
  },
  assistantBubble: {
    backgroundColor: 'rgba(127,127,127,0.12)',
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
    backgroundColor: '#E7F7F2',
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
    color: '#0D5A50',
    fontSize: 14,
    lineHeight: 20,
    fontWeight: '500',
  },
  emptyBox: {
    alignItems: 'center',
    paddingVertical: 36,
    paddingHorizontal: 12,
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
