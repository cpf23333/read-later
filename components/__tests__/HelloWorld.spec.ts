import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import HelloWorld from '../HelloWorld.vue';

describe('HelloWorld', () => {
  it('renders props.msg properly', () => {
    const wrapper = mount(HelloWorld, {
      props: { msg: 'Hello Vitest' },
    });
    expect(wrapper.text()).toContain('Hello Vitest');
  });

  it('increments count on button click', async () => {
    const wrapper = mount(HelloWorld, {
      props: { msg: 'Hello Vitest' },
    });
    const button = wrapper.find('button');
    await button.trigger('click');
    expect(button.text()).toContain('count is 1');
  });
});
